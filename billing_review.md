# Billing Feature — Independent Architectural Review

Target: `frontend/lib/features/billing/**` in the AiClinic Flutter desktop app (`package:ai_clinic`).
Date of review: 2026-07-27.

## Scope & method

**What was reviewed.** All 61 Dart files under `frontend/lib/features/billing/`: 4 files in `data/`, 12 in `domain/`, 1 in `application/`, and 44 in `presentation/` (pages, providers, widgets, models, utils). Every file over 100 lines was read in full; the remainder were read or grepped for the specific concerns below.

**Cross-boundary inspection.** The import graph was extracted with ripgrep in both directions:
- every `package:ai_clinic/features/<other>/...` import inside `features/billing/`, and
- every import of `features/billing/...` from outside `features/billing/`.

Files outside Billing were read only where needed to judge a boundary violation: `core/ui/components/app_money_display.dart`, `core/auth/permission_service.dart`, `core/auth/auth_route_guard.dart`, `core/rpc/rpc_result.dart` usage, `app/router.dart`, `app/app_routes.dart`, and `features/service_catalog/data/service_catalog_repository.dart`. No other feature was reviewed on its own merits.

**Grading baseline.** Findings are graded against the project's own documents, not against generic Clean Architecture dogma:
- `docs/architecture/07-frontend.md` — layer responsibilities table (`domain/` "Depends On: Nothing"; `data/` holds RPC logic; `presentation/` holds pages/widgets/providers), Riverpod provider-type conventions, and the "Layering Inconsistency (Intentional)" table which explicitly permits Billing to skip the `usecases/` layer.
- `docs/architecture/15-billing.md` — billing schema, RPC inventory, permission keys, and business rules (discount mutual exclusivity, partial-payment setting, append-only payments, void preconditions).
- `docs/specs/007-billing/invoice-status-cycle.md` — the authoritative invoice lifecycle and the per-status operation matrix.
- `docs/architecture/01-principles.md` assumption **A3** — business logic lives in PostgreSQL functions, with *orchestration in the Flutter service layer* (not in widgets).
- `docs/architecture/ARCHITECTURAL_FLAWS.md` — pre-existing debt register, used to avoid re-reporting known issues as discoveries.

**Relationship to already-documented flaws.** `ARCHITECTURAL_FLAWS.md` entries **H1** ("Billing marked complete… no presentation layer") and **L2** ("Visits/billing skip use-case layer; repositories called from notifiers") are stale: a full `presentation/` layer now exists. This review does not re-litigate the missing `usecases/` layer, because `07-frontend.md` sanctions repository-calling notifiers for Billing. It *does* report cases where widgets — not notifiers — call repositories, which no document sanctions. Findings M1 and M3 partially overlap known documentation drift and are labelled as such.

**Verdict in brief.** The `data/` and `domain/` layers are largely sound: repositories are thin, typed RPC wrappers with consistent optimistic-concurrency (`expectedUpdatedAt`) plumbing, `Money` is Decimal-backed, and `InvoiceStatus` faithfully mirrors the SQL enum. The problems are concentrated in three places: (1) a money value object that has become a de-facto shared kernel while still living inside Billing, (2) a multi-step invoice-creation orchestration implemented inside a widget with no recovery path, and (3) invoice arithmetic and status/permission rules re-implemented ad hoc in presentation code instead of on the domain objects.

## Findings summary

| ID | Severity | Title | Primary file |
| -- | -------- | ----- | ------------ |
| C1 | Critical | Non-atomic invoice creation orchestrated inside a widget; failure leaves a completed visit with an orphaned unissued draft | `presentation/widgets/visit_billing/visit_billing_flow.dart` |
| C2 | Critical | `Money` shared-kernel value object lives inside Billing and is imported by 4 other features | `domain/money.dart` |
| C3 | Critical | Visit-billing money math uses `double`, and the percentage discount is rounded to a whole number before it is sent | `domain/visit_billing_models.dart` |
| H1 | High | Invoice totals ("amount due", "net paid", "display total") re-derived in three places with three different formulas | `presentation/pages/invoice_detail_page.dart` |
| H2 | High | A billing invoice mutation (`add_invoice_item_from_service`) lives in the Service Catalog repository | `features/service_catalog/data/service_catalog_repository.dart` |
| H3 | High | Two incompatible money formatters with different default currencies; currency resolution owned by Billing presentation | `presentation/utils/billing_formatting.dart` |
| H4 | High | Widgets mutate the ledger through repositories directly, and two write surfaces have no permission gate | `presentation/widgets/void_invoice_dialog.dart` |
| H5 | High | No refund UI: `paid` invoices are a dead end in the documented status cycle | `presentation/widgets/refund_form.dart` |
| H6 | High | Circular presentation-layer coupling between Billing and Visits | `presentation/widgets/visit_billing/visit_billing_flow.dart` |
| H7 | High | 1210-line god file hosting two distinct flows, document layout, and invoice→preview mapping | `presentation/widgets/visit_billing/visit_invoice_review_step.dart` |
| M1 | Medium | Large unreachable write surface (discounts, insurance coverage, discard, provider CRUD, settings toggle) behind placeholder routes | `presentation/providers/invoice_editor_notifier.dart` |
| M2 | Medium | N+1 `get_invoice_detail` fan-out inside a presentation provider, with errors silently swallowed | `presentation/providers/invoice_detail_provider.dart` |
| M3 | Medium | Client-side sort applied to one server page produces globally wrong ordering | `presentation/models/invoice_sort_key.dart` |
| M4 | Medium | Partial-payment business rule implemented in a widget and evaluated with `ref.watch` from a submit path | `presentation/widgets/payment_form.dart` |
| M5 | Medium | Cross-surface cache invalidation is a free function taking `WidgetRef`, callable only from widgets and easy to omit | `presentation/providers/invoice_detail_provider.dart` |
| M6 | Medium | Duplicated balance labels/colours, discount labels, and three custom divider painters across detail, table, and receipt surfaces | `presentation/widgets/receipt_print_preview.dart` |

**Counts:** 3 Critical, 7 High, 6 Medium.

---

# C1 — Non-atomic invoice creation orchestrated inside a widget; failure leaves a completed visit with an orphaned unissued draft

**Severity**: Critical

**Location**
- `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart`
  - `_VisitBillingFlowState._handleFinalize()` — lines 73–149
  - `_VisitBillingFlowState._createAndIssueInvoice()` — lines 151–214
- Collaborators: `frontend/lib/features/billing/data/invoice_repository.dart` (`InvoiceRepository`), `frontend/lib/features/service_catalog/data/service_catalog_repository.dart` (`ServiceCatalogRepository.addInvoiceItemFromService`), `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` (`visitDocumentationProvider(...).notifier.completeVisit()`)

**Issue**

`_createAndIssueInvoice` performs the entire draft→issued invoice lifecycle from inside a `ConsumerState`, by reading two repositories directly (`ref.read(invoiceRepositoryProvider)` line 158, `ref.read(serviceCatalogRepositoryProvider)` line 159). The sequence is:

1. `createFromVisit(visitId)` → new draft id (line 161)
2. `getDetail(invoiceId)` to obtain `updatedAt` (line 162)
3. for every selected line: `addInvoiceItemFromService(...)` then another `getDetail(...)` (lines 164–171)
4. if `quantity > 1`: `updateItem(...)` then another `getDetail(...)` (lines 173–185)
5. optionally `applyInvoiceDiscount(...)` then another `getDetail(...)` (lines 188–207)
6. `issue(...)` then a final `getDetail(...)` (lines 209–213)

That is `3 + 2N` (up to `3 + 3N`) sequential RPC round-trips driven by widget state, with no transaction, no compensating action, and no resume path.

`_handleFinalize` (line 89) calls `docNotifier.completeVisit()` **before** creating the invoice — which is mandatory, because the backend rejects `create_invoice_from_visit` on a non-completed visit (`VISIT_NOT_COMPLETED`, mapped in `frontend/lib/features/billing/application/billing_rpc_messages.dart` line 9). But the failure handling (lines 101–107) shows a toast and `return`s from inside the `try`, which means:

- the visit is already `completed` and cannot be un-completed;
- a `draft` invoice may already exist with a partial set of line items;
- `VisitSubmittedDialog.show(...)` (line 125) never runs, so the operator gets no confirmation of the visit they just finalized;
- `billingNotifier.reset()` (line 124) never runs, so the wizard keeps stale selections;
- a retry re-enters `createFromVisit` and fails with `ACTIVE_INVOICE_EXISTS` (`billing_rpc_messages.dart` line 8) because of the one-active-invoice-per-visit partial unique index documented in `docs/specs/007-billing/invoice-status-cycle.md` § "One active invoice per visit". The operator is now permanently stuck for that visit with no UI path to the half-built draft.

Separately, when `permissions.canCreateInvoices()` is `false` (line 92) the whole invoice block is skipped silently: the visit is completed and no invoice is ever created, with no message explaining that billing was skipped.

**Why it is a problem**

This is a money-correctness and recoverability defect, not a style issue. A single network blip mid-loop produces a completed clinical visit with an unissued, partially-populated invoice that no screen can reach (the invoice list filters include `draft`, but the operator has no reason to know to look there, and the visit-billing wizard cannot resume). It also violates `01-principles.md` assumption A3, which places orchestration in "the Flutter service layer", and `07-frontend.md`'s layer table, which puts RPC logic in `data/` and consumption in providers — not in widget state. Because the sequence lives in a `State` class it cannot be unit-tested without pumping widgets, so the highest-risk code path in the feature is effectively untestable.

**Recommended architectural solution**

Move the orchestration into a new application-layer service and let the notifier own the outcome, so the widget only renders results.

1. New file `frontend/lib/features/billing/application/visit_invoice_finalization_service.dart` containing:
   - `class VisitInvoiceFinalizationService` with constructor `VisitInvoiceFinalizationService(this._invoices, this._invoiceItems)`; fields typed `InvoiceRepository` and `InvoiceItemRepository` (the latter is created in finding **H2**; until H2 lands, type it `ServiceCatalogRepository`).
   - `Future<InvoiceDetail> createIssuedInvoiceForVisit({required String visitId, required List<VisitSelectedServiceLine> lines, required VisitBillingDiscountType discountType, required Decimal discountValue, required bool canApplyDiscount})` — the body is the current `_createAndIssueInvoice` moved verbatim, except step 1 is replaced by `resolveOrCreateDraft` below and the discount value is no longer rounded (see **C3**).
   - `Future<String> resolveOrCreateDraft(String visitId)` — calls `InvoiceRepository.findForVisit(visitId: visitId)` (already exists, `data/invoice_repository.dart` line 237); if it returns an item whose `status.isDraft`, reuse `item.id`; otherwise call `createFromVisit`. This makes the whole operation idempotent on retry.
   - `final visitInvoiceFinalizationServiceProvider = Provider<VisitInvoiceFinalizationService>(...)` wiring the two repository providers.
2. New file `frontend/lib/features/billing/application/visit_finalize_outcome.dart` containing a sealed result type so the widget never interprets exceptions:
   - `sealed class VisitFinalizeOutcome`
   - `final class VisitFinalizeSucceeded extends VisitFinalizeOutcome` — fields `VisitDetail visit`, `InvoiceDetail? invoice` (null when the user lacks `invoices.create`)
   - `final class VisitFinalizeInvoiceFailed extends VisitFinalizeOutcome` — fields `VisitDetail visit`, `String message`, `String? draftInvoiceId` (visit *is* completed; invoice needs retry)
   - `final class VisitFinalizeVisitFailed extends VisitFinalizeOutcome` — field `String message`
3. Extend `frontend/lib/features/billing/presentation/providers/visit_billing_flow_notifier.dart` with `Future<VisitFinalizeOutcome> finalize()`, which sets `isSubmitting`, calls `completeVisit()`, then the service, maps `RpcFailure` through `billingMessageForRpc` / `visitMessageForRpc`, and always clears `isSubmitting`. The notifier keeps `draftInvoiceId` in its state so a second `finalize()` call resumes instead of restarting.
4. `visit_billing_flow.dart` keeps only: call `finalize()`, `switch` on the outcome, and for each case show `VisitSubmittedDialog` (success, possibly with `persistedInvoice: null`), or the dialog plus a danger toast and a "Retry invoice" affordance (`VisitFinalizeInvoiceFailed`), or a toast only (`VisitFinalizeVisitFailed`). Crucially, `VisitFinalizeInvoiceFailed` must still show the visit-submitted confirmation, because the visit really was completed.
5. Also show an explicit informational toast when `canCreateInvoices()` is false, so "no invoice was created" is a visible decision rather than silence.

Round-trip count is deliberately left unchanged: every mutation RPC requires a fresh `expected_updated_at`, and the RPCs return only ids. Reducing the chatter requires the backend mutation RPCs to return the new `updated_at`; that is a separate backend change and out of scope here.

**Suggested implementation steps**

1. Create `frontend/lib/features/billing/application/visit_finalize_outcome.dart` with the four classes listed above. No logic.
2. Create `frontend/lib/features/billing/application/visit_invoice_finalization_service.dart`. Copy the body of `_createAndIssueInvoice` from `visit_billing_flow.dart` lines 151–214 into `createIssuedInvoiceForVisit`. Replace `ref.read(invoiceRepositoryProvider)` / `ref.read(serviceCatalogRepositoryProvider)` with the injected fields. Add `resolveOrCreateDraft` and use it in place of the bare `createFromVisit` call.
3. Add `visitInvoiceFinalizationServiceProvider` at the bottom of that file, reading `invoiceRepositoryProvider` and `serviceCatalogRepositoryProvider`.
4. In `visit_billing_flow_notifier.dart`: add a nullable `String? draftInvoiceId` to the state class and its `copyWith`; add `Future<VisitFinalizeOutcome> finalize()` that performs the sequence described above; move the `try/catch/finally` and the `setSubmitting` calls here.
5. In `visit_billing_flow.dart`: delete `_createAndIssueInvoice` entirely; reduce `_handleFinalize` to `final outcome = await ref.read(visitBillingFlowProvider(widget.visitId).notifier).finalize();` followed by a `switch (outcome)`; delete the now-unused imports of `billing/data/invoice_repository.dart`, `service_catalog/data/service_catalog_repository.dart`, `core/rpc/rpc_result.dart`, `billing/application/billing_rpc_messages.dart`, `visits/application/visit_rpc_messages.dart` and `billing/domain/discount_kind.dart`.
6. Verify by `flutter analyze` (no unused imports, no remaining reference to `_createAndIssueInvoice`), then manually: finalize a visit with 2 services where one has quantity 2 and a 10% discount, confirm the issued invoice matches; then finalize with the network dropped after the first item is added, confirm the visit-submitted dialog still appears with a "retry invoice" path, and confirm the retry succeeds and reuses the same draft rather than failing with `ACTIVE_INVOICE_EXISTS`.

---

# C2 — `Money` shared-kernel value object lives inside Billing and is imported by four other features

**Severity**: Critical

**Location**
- Definition: `frontend/lib/features/billing/domain/money.dart` — `class Money implements Comparable<Money>` (Decimal-backed; `parse`, `tryParse`, `fromWire`, `wireValue`, `asDouble`, `isZero/isPositive/isNegative`, `operator +`, `operator -`)
- Consumers outside Billing (13 import sites):
  - `frontend/lib/features/service_catalog/domain/service.dart`
  - `frontend/lib/features/service_catalog/domain/service_list_item.dart`
  - `frontend/lib/features/service_catalog/domain/service_branch_config.dart`
  - `frontend/lib/features/service_catalog/domain/service_promotion.dart`
  - `frontend/lib/features/service_catalog/domain/effective_price.dart`
  - `frontend/lib/features/service_catalog/domain/eligible_service.dart`
  - `frontend/lib/features/service_catalog/application/service_form_validation.dart`
  - `frontend/lib/features/service_catalog/application/promotion_validation.dart`
  - `frontend/lib/features/service_catalog/presentation/utils/service_price_preview.dart`
  - `frontend/lib/features/setup/domain/persist_clinic_setup_draft.dart`
  - `frontend/lib/features/patients/presentation/widgets/patient_invoice_card.dart`
  - plus `features/billing/domain/visit_billing_models.dart` importing `service_catalog/domain/eligible_service.dart` in the opposite direction

**Issue**

`Money` is the application's only currency-safe numeric type, but it is filed as a Billing domain object. Four unrelated features (`service_catalog`, `setup`, `patients`, and transitively anything using an `EligibleService`) must import `package:ai_clinic/features/billing/domain/money.dart` to express a price. The dependency is also cyclic at the feature level: `billing/domain/visit_billing_models.dart` imports `service_catalog/domain/eligible_service.dart`, while every `service_catalog` domain file imports `billing/domain/money.dart`.

**Why it is a problem**

`07-frontend.md`'s layer table states the `domain/` layer "Depends On: Nothing", and the feature-first structure implies features are peers, not libraries for each other. Today Billing is an implicit dependency of the Service Catalog, so Billing cannot be modified, extracted, or tested in isolation, and no new feature can represent a price without taking a Billing dependency. Concretely: adding a needed operation to `Money` (multiplication, which finding **C3** requires) is currently a change to the Billing feature that recompiles and re-risks the Service Catalog and Setup wizard. The cycle also blocks any future move to per-feature packages, and it makes the dependency graph misleading to anyone reasoning about blast radius.

**Recommended architectural solution**

Promote `Money` to `core/` as a shared kernel type, which is exactly what `07-frontend.md` describes `core/` for (`core/errors/`, `core/rpc/`, `core/ui/` are already shared kernels).

- New file `frontend/lib/core/money/money.dart` containing the `Money` class verbatim (same class name, same public API), plus the new operations required by **C3**: `Money operator *(int quantity)`, `Money percentageOf(Decimal percent)` (multiply then `round(scale: 2)`), and `Money clampToZeroAnd(Money max)`.
- Delete `frontend/lib/features/billing/domain/money.dart`. Do **not** leave a re-export shim — a shim preserves the false dependency in the import graph and future code will keep importing it.

**Suggested implementation steps**

1. Create `frontend/lib/core/money/money.dart`. Paste the entire current contents of `frontend/lib/features/billing/domain/money.dart` into it unchanged (keep `import 'package:decimal/decimal.dart';` and `import 'package:flutter/foundation.dart';`).
2. Append the three new methods to the class: `Money operator *(int quantity)` returning `Money._(_value * Decimal.fromInt(quantity))`; `Money percentageOf(Decimal percent)`; `Money clampToZeroAnd(Money max)`. Keep the private `Money._` constructor.
3. Delete `frontend/lib/features/billing/domain/money.dart`.
4. Replace the import string `package:ai_clinic/features/billing/domain/money.dart` with `package:ai_clinic/core/money/money.dart` in every file that references it. The Billing files are: `domain/invoice_detail.dart`, `domain/invoice_item.dart`, `domain/invoice_list_item.dart`, `domain/payment.dart`, `presentation/pages/invoice_detail_page.dart`, `presentation/utils/billing_formatting.dart`, `presentation/widgets/invoice_detail/invoice_hero_card.dart`, `presentation/widgets/invoice_detail/invoice_totals_panel.dart`, `presentation/widgets/receipt_print_preview.dart`, `presentation/widgets/visit_billing/visit_invoice_summary_panel.dart`. The non-Billing files are the 11 listed under **Location** above.
5. Run `rg -n "features/billing/domain/money.dart" frontend/lib` and confirm zero matches.
6. Run `flutter analyze` and confirm no new diagnostics. There is no behaviour change to verify at runtime; this step is purely a move.

---

# C3 — Visit-billing money math uses `double`, and the percentage discount is rounded to a whole number before it is sent

**Severity**: Critical

**Location**
- `frontend/lib/features/billing/domain/visit_billing_models.dart`
  - `VisitSelectedServiceLine.unitPrice` is `double` (line 25); `double get lineTotal => unitPrice * quantity` (line 28)
  - `VisitSelectedServiceLine.fromEligibleService` drops precision via `service.unitPrice.asDouble` (line 45)
  - `class VisitBillingTotals` — `subtotal`, `discountAmount`, `total` all `double` (lines 60–62)
  - `computeVisitBillingTotals(...)` — `fold<double>`, `subtotal * discountValue / 100`, `clamp` (lines 67–91)
  - `VisitBillingInvoicePreview` — `discountValue`, `subtotal`, `discountAmount`, `total` all `double` (lines 109–112)
- `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart`
  - discount serialization: `discountValue.round().toString()` for percentage, `discountValue.toStringAsFixed(2)` for fixed (lines 201–203)
- `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart`
  - `_totalsFromInvoice(InvoiceDetail)` (lines 464–472) — recomputes `subtotal - discountAmount` in `double` and **omits `insuranceCoveredAmount` entirely**
  - `_linesFromInvoiceItems(...)` (lines 426–438) — `item.unitPrice.asDouble`, and sets `serviceId: item.id` (an invoice-item id, not a catalog service id)

**Issue**

The whole app parses server amounts into the Decimal-backed `Money` type, then the visit-billing wizard converts them back to IEEE-754 `double` and does the arithmetic there. Three distinct defects follow:

1. **Float drift.** `subtotal` is accumulated with `fold<double>` over `unitPrice * quantity`. Prices such as `0.10` and `1.15` are not exactly representable; a multi-line invoice preview can differ from the server total by fractions of a cent, and the discount is then computed off that drifted subtotal.
2. **Silent percentage truncation.** `visit_billing_flow.dart` line 202 sends `discountValue.round().toString()`. The discount field accepts fractional percentages, and `computeVisitBillingTotals` previews them faithfully (`subtotal * discountValue / 100`), but the value actually persisted is rounded to an integer. A user who previews a 12.5% discount has 13% applied — the operator sees one total on screen and a different total on the issued invoice. `presentation/utils/billing_formatting.dart` `discountLabel` (line 84) also renders `${parsed.round()}%`, so the mismatch stays invisible after the fact.
3. **Insurance omitted from the read-only review.** `_totalsFromInvoice` computes `total = subtotal - discountAmount`. It is used by `VisitInvoiceReadOnlyReview`, which is the body of the `/billing/invoices/:id/review` page (`presentation/pages/invoice_review_page.dart`). For any invoice with `insuranceCoveredAmount > 0`, that page presents a "total" that is neither the amount due nor the balance, while `InvoiceDetail.balance` (authoritative, server-computed) sits unused on the same object.

**Why it is a problem**

`docs/specs/007-billing/invoice-status-cycle.md` § "Balance drives payment statuses" defines the money identities exactly (`balance = subtotal − discount_amount − insurance_covered_amount − Σ payments`), and the server is the source of truth. Any client-side re-derivation in `double` is a second, less accurate implementation of a financial contract. Defect 2 is a real correctness bug that changes how much a patient is charged relative to what staff approved on screen; defects 1 and 3 make the UI disagree with the invoice it is describing. These are the highest-consequence class of bug in a billing module, and the drift is invisible in testing until an amount happens to land on an unrepresentable value.

**Recommended architectural solution**

Make `Money` (relocated to `core/money/money.dart` by finding **C2**) the only currency type in the visit-billing path, keep the user-entered discount as a `Decimal`, and never re-derive a total the server already computed.

- Retype in `frontend/lib/features/billing/domain/visit_billing_models.dart`: `VisitSelectedServiceLine.unitPrice` → `Money`; `lineTotal` → `Money get lineTotal => unitPrice * quantity` (uses the new `operator *(int)` from C2); `VisitBillingTotals.{subtotal, discountAmount, total}` → `Money`; `VisitBillingInvoicePreview.{subtotal, discountAmount, total}` → `Money` and `discountValue` → `Decimal`.
- `computeVisitBillingTotals(List<VisitSelectedServiceLine> lines, VisitBillingDiscountType type, Decimal discountValue)` folds with `Money.zero` and computes the percentage branch as `subtotal.percentageOf(discountValue)` and the fixed branch as `Money`-clamped to `subtotal` via `clampToZeroAnd`.
- `VisitBillingFlowState.discountValue` in `frontend/lib/features/billing/presentation/providers/visit_billing_flow_notifier.dart` becomes `Decimal`; `setDiscountValue` accepts the raw string from `AppMoneyField`/`AppNumberInput` and parses with `Decimal.tryParse`, defaulting to `Decimal.zero`.
- The wire value sent to `apply_invoice_discount` becomes `discountValue.toString()` for percentage (no `.round()`) and `Money`-formatted `wireValue` for fixed. `InvoiceRepository.applyInvoiceDiscount` already takes `String? value`, so its signature is unchanged.
- Delete `_totalsFromInvoice` and `_discountFromInvoice`/`_linesFromInvoiceItems`' role in totals. Instead add read-only getters to `frontend/lib/features/billing/domain/invoice_detail.dart` (see finding **H1**): `Money get originalDue`, `Money get netPaid`, and have `VisitInvoiceReadOnlyReview` render `invoice.subtotal`, `invoice.discountAmount`, `invoice.insuranceCoveredAmount`, `invoice.originalDue` and `invoice.balance` directly from the server payload.

**Suggested implementation steps**

1. Complete finding **C2** first (`Money` in `core/money/money.dart` with `operator *(int)`, `percentageOf(Decimal)`, `clampToZeroAnd(Money)`).
2. In `domain/visit_billing_models.dart`: change the four `double` fields listed above to `Money`; change `computeVisitBillingTotals`' third parameter to `Decimal`; rewrite its body with `Money` operations; change `fromEligibleService` to pass `service.unitPrice` straight through (delete `.asDouble`). Change `VisitBillingInvoicePreview.discountValue` to `Decimal`.
3. In `presentation/providers/visit_billing_flow_notifier.dart`: change `discountValue` to `Decimal` in the state class, `copyWith`, and the initial value (`Decimal.zero`); update `setDiscountValue` to parse the incoming string; the `totals` getter needs no change beyond the new parameter type.
4. In `presentation/widgets/visit_billing/visit_invoice_review_step.dart`: replace every `totals.subtotal` / `totals.discountAmount` / `totals.total` usage that feeds `AppMoneyDisplay(amount: ...)` with `<money>.asDouble` at the widget boundary only (display conversion is acceptable; arithmetic is not). Update `_DiscountSidebar`, `_ReadOnlyDiscountSidebar` and `_fixedDiscountExceedsSubtotal` to compare `Money`/`Decimal` rather than `double`. Delete `_totalsFromInvoice`.
5. In `presentation/widgets/visit_billing/visit_invoice_summary_panel.dart`, `visit_service_selection_grid_view.dart`, `visit_service_selection_list_view.dart`, `visit_service_selection_sidebar.dart` and `visit_service_selection_step.dart`: adjust the `unitPrice`/`lineTotal` call sites to append `.asDouble` where they are passed to `AppMoneyDisplay`, and to use `Money` comparisons elsewhere.
6. In `presentation/widgets/visit_billing/visit_billing_flow.dart` (or, after **C1**, in `application/visit_invoice_finalization_service.dart`): change the discount serialization to `discountValue.toString()` for `VisitBillingDiscountType.percentage` and to the `Money.wireValue` of the fixed amount for `VisitBillingDiscountType.fixed`. Remove `.round()` and `.toStringAsFixed(2)`.
7. In `presentation/utils/billing_formatting.dart` `discountLabel`: stop rounding — parse with `Decimal.tryParse` and render the value as entered (trim a trailing `.0` if desired), so the label matches what was persisted.
8. In `domain/invoice_detail.dart`: add `Money get originalDue => subtotal - discountAmount - insuranceCoveredAmount;` and `Money get netPaid => payments.fold(Money.zero, (sum, p) => sum + p.amount);`.
9. In `VisitInvoiceReadOnlyReview` (inside `visit_invoice_review_step.dart`, extracted by **H7**): render totals from `invoice.subtotal`, `invoice.discountAmount`, `invoice.insuranceCoveredAmount`, `invoice.originalDue`, `invoice.balance`. Do not compute anything.
10. Verify: `flutter analyze`; then create a draft with two services priced `0.10` and `1.15` at quantity 3 and confirm the preview subtotal reads exactly `3.75`; apply a `12.5%` discount and confirm the issued invoice's `discount_value` is `12.5` and its `discount_amount` matches the preview; open `/billing/invoices/:id/review` for an invoice with insurance coverage and confirm the displayed amount due equals `subtotal − discount − insurance`.

---

# H1 — Invoice totals re-derived in three places with three different formulas

**Severity**: High

**Location**
- `frontend/lib/features/billing/presentation/pages/invoice_detail_page.dart`
  - `_InvoiceDetailBodyState._amountDue()` — line 175: `invoice.subtotal - invoice.discountAmount - invoice.insuranceCoveredAmount`
  - `_InvoiceDetailBodyState._netPaid()` — lines 177–179: `invoice.payments.fold(Money.zero, ...)`
- `frontend/lib/features/billing/domain/invoice_list_item.dart`
  - `String get displayTotal => (subtotal - discountAmount).wireValue;` — line 48 (insurance deliberately excluded, per its comment)
- `frontend/lib/features/billing/presentation/pages/invoice_editor_page.dart`
  - `final netTotal = invoice.subtotal - invoice.discountAmount;` — line 169 (a third formula)
- `frontend/lib/features/billing/presentation/widgets/receipt_print_preview.dart`
  - `paidTotal = invoice.payments.fold<Money>(Money.zero, ...)` — line 128 (duplicate of `_netPaid`)
- `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart`
  - `_totalsFromInvoice` — lines 464–472 (a fourth formula; see **C3**)

**Issue**

`docs/specs/007-billing/invoice-status-cycle.md` defines two derived quantities precisely: *original due* = `subtotal − discount_amount − insurance_covered_amount`, and *net paid* = the signed sum of the payment ledger (refunds are negative rows). Neither exists on `InvoiceDetail`. Instead:

- "amount due" is computed in a private method of a page `State` class,
- "net paid" is computed identically in that page and again in the PDF builder,
- the invoice list row exposes `displayTotal` which is a *different* quantity (ignores insurance) under a name that reads like a total,
- the editor page computes a fourth variant inline as `netTotal`.

`InvoiceDetail` and `InvoiceListItem` both carry the server's authoritative `balance`, so the client is re-deriving neighbours of a value it already has.

**Why it is a problem**

The financial identities of the domain are scattered across four presentation files, so there is no single place to read, review, or test them. Nothing prevents the next surface from adding a fifth variant, and nothing flags that `displayTotal` and `_amountDue()` mean different things — a reviewer comparing the invoice list to the invoice detail sees two numbers labelled similarly that legitimately differ for insured invoices. `07-frontend.md` places value objects and DTO logic in `domain/`; derived money is exactly that. It is also untestable today: verifying "amount due" requires pumping `InvoiceDetailPage`.

**Recommended architectural solution**

Put the derived quantities on the domain objects, with names taken from the status-cycle document, and delete every presentation-side re-derivation.

- In `frontend/lib/features/billing/domain/invoice_detail.dart`, add to `class InvoiceDetail`:
  - `Money get originalDue => subtotal - discountAmount - insuranceCoveredAmount;`
  - `Money get netPaid => payments.fold(Money.zero, (sum, payment) => sum + payment.amount);`
  - `Money get netTotal => subtotal - discountAmount;` (the pre-insurance figure the editor needs)
- In `frontend/lib/features/billing/domain/invoice_list_item.dart`, rename `displayTotal` to `Money get netTotal => subtotal - discountAmount;` (return `Money`, not `String`; let the widget format it) and add `Money get originalDue => subtotal - discountAmount - insuranceCoveredAmount;`.
- Presentation code reads these getters and `invoice.balance`; it never subtracts money itself.

**Suggested implementation steps**

1. In `domain/invoice_detail.dart`: add the three getters `originalDue`, `netPaid`, `netTotal` to `InvoiceDetail` (place them directly after the field declarations, before `fromRpcData`).
2. In `domain/invoice_list_item.dart`: replace `String get displayTotal` with `Money get netTotal => subtotal - discountAmount;` and add `Money get originalDue`.
3. In `presentation/pages/invoice_detail_page.dart`: delete `_amountDue()` and `_netPaid()`; replace `final amountDue = _amountDue();` with `final amountDue = invoice.originalDue;` and `final netPaid = _netPaid();` with `final netPaid = invoice.netPaid;` (lines 264–265). The rest of `build` is unchanged.
4. In `presentation/pages/invoice_editor_page.dart` line 169: replace the inline subtraction with `final netTotal = invoice.netTotal;`.
5. In `presentation/widgets/receipt_print_preview.dart` line 128: replace the fold with `final paidTotal = invoice.netPaid;`.
6. In `presentation/widgets/visit_billing/visit_invoice_review_step.dart`: delete `_totalsFromInvoice` and read `invoice.subtotal` / `invoice.discountAmount` / `invoice.insuranceCoveredAmount` / `invoice.originalDue` / `invoice.balance` in `VisitInvoiceReadOnlyReview` (coordinated with **C3** step 9).
7. Search for the old name: `rg -n "displayTotal" frontend/lib` and update each call site to `netTotal` plus `BillingFormatting.formatMoney(...)` or `AppMoneyDisplay(amount: ....asDouble)` as the surrounding widget requires (expected sites: `presentation/widgets/invoice_table.dart`, `features/patients/presentation/widgets/patient_invoice_card.dart`).
8. Verify with `flutter analyze`, then open one invoice that has both a discount and insurance coverage and confirm the detail page, the list row, the editor, and the printed receipt all show mutually consistent numbers, with "Balance due" equal to the server's `balance`.

---

# H2 — A billing invoice mutation lives in the Service Catalog repository

**Severity**: High

**Location**
- `frontend/lib/features/service_catalog/data/service_catalog_repository.dart`
  - `class AddInvoiceItemFromServiceResult` — lines 21–33
  - `ServiceCatalogRepository.addInvoiceItemFromService({required String invoiceId, required DateTime expectedUpdatedAt, required String serviceId})` — lines 319–347, calling RPC `add_invoice_item_from_service` with `p_invoice_id` / `p_expected_updated_at` / `p_service_id`
- Billing callers that therefore import another feature's `data/` layer:
  - `frontend/lib/features/billing/presentation/providers/invoice_editor_notifier.dart` line 9 (import) and `InvoiceEditorNotifier.addItemFromService` lines 106–115
  - `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart` line 12 (import) and `_createAndIssueInvoice` line 165

**Issue**

`add_invoice_item_from_service` writes an `invoice_items` row, takes the invoice's optimistic-concurrency token (`expectedUpdatedAt`), and can fail with billing error codes (`STALE_INVOICE`, `INVOICE_NOT_IN_DRAFT`). It is an invoice mutation whose only catalog involvement is that the priced line is resolved from a `service_id`. It is nevertheless implemented on `ServiceCatalogRepository`, whose `migrationHint` and `rpcLogDomain` point at the catalog, so billing write failures are logged under the catalog RPC domain.

Consequently Billing's editor notifier and its visit-billing widget both import `features/service_catalog/data/...` — reaching into a peer feature's data layer, which is the strictest boundary in the layer table.

**Why it is a problem**

Ownership is inverted: the Service Catalog now knows about invoice ids, invoice revisions, and draft-state preconditions, and Billing cannot add, wrap, or change behaviour of one of its own line-item mutations without editing another feature. Error mapping is also split — `billingMessageForRpc` handles the failure codes, but the invocation is logged and hinted as a catalog call, so diagnosing a stale-invoice failure sends the reader to the wrong migration. Any future change to the invoice concurrency protocol (for example returning the new `updated_at`) has to be made in two features at once.

**Recommended architectural solution**

Move the wrapper into Billing's data layer and let Billing depend on the Service Catalog only through its `domain/` DTOs (which is acceptable and already the pattern for `EligibleService`).

- New file `frontend/lib/features/billing/data/invoice_item_repository.dart` containing:
  - `class AddInvoiceItemFromServiceResult` (moved verbatim: `itemId`, `quantity`, `unitPrice`, `appliedRule`)
  - `class InvoiceItemRepository with AppRpcInvoker` — `rpcClient` from `supabaseClientProvider`, `migrationHint` set to the billing migration that defines the RPC, `rpcLogDomain = 'billing.invoice_items'`
  - `Future<AddInvoiceItemFromServiceResult> addFromService({required String invoiceId, required DateTime expectedUpdatedAt, required String serviceId})` — body moved verbatim
  - `final invoiceItemRepositoryProvider = Provider<InvoiceItemRepository>(...)`
- Delete `addInvoiceItemFromService` and `AddInvoiceItemFromServiceResult` from `ServiceCatalogRepository`.

**Suggested implementation steps**

1. Create `frontend/lib/features/billing/data/invoice_item_repository.dart`. Copy `class AddInvoiceItemFromServiceResult` (lines 21–33) and the body of `addInvoiceItemFromService` (lines 319–347) out of `frontend/lib/features/service_catalog/data/service_catalog_repository.dart`. Rename the method to `addFromService`. Mirror the mixin wiring used by `frontend/lib/features/billing/data/invoice_repository.dart` (`with AppRpcInvoker`, `SupabaseClient get rpcClient => _client;`, `String get migrationHint`, `String get rpcLogDomain => 'billing.invoice_items';`). Copy the private `_assertNonEmpty` helper from `invoice_repository.dart` so the input assertions still throw `RpcFailure(... 'INVALID_INPUT' ...)`.
2. Add `final invoiceItemRepositoryProvider = Provider<InvoiceItemRepository>((ref) => InvoiceItemRepository(ref.watch(supabaseClientProvider)));` at the bottom of the new file.
3. Delete `addInvoiceItemFromService` and `AddInvoiceItemFromServiceResult` from `service_catalog_repository.dart`. Remove any imports that become unused there.
4. In `frontend/lib/features/billing/presentation/providers/invoice_editor_notifier.dart`: replace the import of `features/service_catalog/data/service_catalog_repository.dart` with `features/billing/data/invoice_item_repository.dart`; change `ServiceCatalogRepository get _catalogRepo => ref.read(serviceCatalogRepositoryProvider);` to `InvoiceItemRepository get _itemRepo => ref.read(invoiceItemRepositoryProvider);`; in `addItemFromService` call `_itemRepo.addFromService(...)`. Keep the `features/service_catalog/domain/eligible_service.dart` import — a domain-only dependency is fine.
5. In `frontend/lib/features/billing/application/visit_invoice_finalization_service.dart` (created by **C1**; or `visit_billing_flow.dart` if C1 has not landed): inject `InvoiceItemRepository` instead of `ServiceCatalogRepository` and call `addFromService`.
6. Run `rg -n "addInvoiceItemFromService|serviceCatalogRepositoryProvider" frontend/lib/features/billing` and confirm zero matches.
7. Verify with `flutter analyze`, then add a catalog service to a draft invoice from `/billing/invoices/:id/edit` and confirm the line appears with the promotion-derived price and that a stale-revision attempt still surfaces "This invoice was updated elsewhere."

---

# H3 — Two incompatible money formatters with different default currencies; currency resolution owned by Billing presentation

**Severity**: High

**Location**
- Formatter A: `frontend/lib/features/billing/presentation/utils/billing_formatting.dart` — `BillingFormatting.formatMoney(Money amount, {String currency = 'USD', String? locale})` (lines 11–36) with a symbol map `_currencySymbol` covering only `USD`, `EUR`, `GBP`, `EGP` (lines 38–46). Produces e.g. `$1,234.00`.
- Formatter B: `frontend/lib/core/ui/components/app_money_display.dart` — `AppMoneyDisplay({required double amount, String currency = 'EGP', ...})` (lines 9–24) with `static final _formatter = NumberFormat('#,##0.00', 'en_EG')` (line 24). Ignores `currency` for formatting and appends the raw code as a trailing text span (lines 77–81). Produces e.g. `1,234.00 USD`.
- Currency resolution: `frontend/lib/features/billing/presentation/providers/organization_currency_provider.dart` — `organizationCurrencyProvider`, which reads `clinicSetupOrganizationProvider` from `features/clinic-management/presentation/providers/clinic_setup_providers.dart` and falls back to `'USD'` (line 16).
- Cross-feature consumers of Billing's presentation utilities:
  - `frontend/lib/features/patients/presentation/widgets/patient_invoice_card.dart` imports `billing/presentation/utils/billing_formatting.dart`, `billing/presentation/utils/payment_method_l10n.dart`, and `billing/presentation/providers/organization_currency_provider.dart`
  - `frontend/lib/features/service_catalog/presentation/utils/service_price_preview.dart` imports `billing/presentation/utils/billing_formatting.dart`
- Additional silent defaults: `InvoiceDetail.fromRpcData` defaults `currency` to `'USD'` (`domain/invoice_detail.dart` line 188); `InvoiceListItem.fromRow` does the same (`domain/invoice_list_item.dart` lines 91–93).

**Issue**

Money is rendered by two different components that disagree on both format and default. Within the Billing feature itself, `invoice_totals_panel.dart`, `invoice_hero_card.dart`, `payment_form.dart` and the visit-billing widgets use `AppMoneyDisplay` (code suffix, `en_EG` grouping, default `EGP`), while `billing_formatting.dart`'s `formatMoney`, and the surfaces that call it, use a currency symbol prefix and default `USD`. So the same invoice can be presented as `$450.00` on one surface and `450.00 USD` on another, and a caller that forgets to pass `currency` gets `USD` in one component and `EGP` in the other.

The currency *value* is resolved by a provider that lives in `billing/presentation/providers/` but reads `clinic-management`'s presentation provider, and is then consumed by `patients`. So a Patients widget depends on Billing presentation, which depends on Clinic Management presentation, to answer "what currency is this clinic in?".

**Why it is a problem**

The review objective explicitly asks whether money/currency handling is centralized; it is not. There is no single answer to "how is an amount rendered" or "what currency applies", which makes inconsistent output inevitable rather than accidental, and it means fixing a formatting bug requires finding all call sites of two components. The `'USD'`/`'EGP'` split is worse than a cosmetic default: an invoice row whose `currency` column is null renders as USD, while a `AppMoneyDisplay` with an omitted argument renders as EGP, on the same screen. And because currency resolution sits in a feature's presentation layer, two unrelated features (`patients`, `service_catalog`) have a compile-time dependency on Billing purely to format a price.

**Recommended architectural solution**

One formatter and one currency source, both in `core/`.

- New file `frontend/lib/core/money/money_formatter.dart` with `abstract final class MoneyFormatter` exposing `String format(Money amount, {required String currency, String? locale})` — the body is `BillingFormatting.formatMoney`'s implementation, with the `_currencySymbol` map moved here. No default currency: the parameter is required, so a missing currency becomes a compile error rather than a wrong render.
- New file `frontend/lib/core/money/organization_currency_provider.dart` holding `organizationCurrencyProvider` (moved unchanged). It may still watch `clinicSetupOrganizationProvider`; the point is that consumers depend on `core/`, not on Billing.
- Rewrite `AppMoneyDisplay` to take `required Money amount` and `required String currency` and to render via `MoneyFormatter.format`, deleting its private `_formatter` and its `'EGP'` default. Keep the negative-styling and typography logic (`_baseTextStyle`, `statusDangerFg`, tabular figures) — that is genuinely presentational and worth keeping.
- Delete `BillingFormatting.formatMoney` and `_currencySymbol`; keep the rest of `BillingFormatting` (`formatDate`, `formatDateTime`, `invoiceDisplayNumber`, `paymentMethodIcon`, `discountLabel`) as billing-specific presentation helpers.

**Suggested implementation steps**

1. Create `frontend/lib/core/money/money_formatter.dart`. Move `formatMoney` (rename to `format`) and `_currencySymbol` from `billing_formatting.dart` into `abstract final class MoneyFormatter`. Make `currency` a required named parameter. Keep the existing `try/catch` fallback that returns `'$symbol$wireValue'` / `'$wireValue $currency'`.
2. Create `frontend/lib/core/money/organization_currency_provider.dart` and move `organizationCurrencyProvider` there verbatim. Delete `frontend/lib/features/billing/presentation/providers/organization_currency_provider.dart`.
3. Update the import in every file that referenced the old provider path: `billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart`, `.../visit_service_selection_step.dart`, `.../visit_invoice_summary_panel.dart`, and `features/patients/presentation/widgets/patient_invoice_card.dart`.
4. Edit `frontend/lib/core/ui/components/app_money_display.dart`: change `final double amount` to `final Money amount`, make `currency` required (remove `= 'EGP'`), delete `_formatter`, and in `build` compute `final formatted = MoneyFormatter.format(amount, currency: currency);` and `final isNegative = negative ?? amount.isNegative;`. Render `formatted` as the single amount span and drop the separate trailing currency span (the formatter already includes the symbol or code).
5. Fix every `AppMoneyDisplay` call site to pass a `Money` instead of `.asDouble` and to pass `currency:` explicitly. Find them with `rg -n "AppMoneyDisplay\(" frontend/lib`. Known Billing sites: `presentation/widgets/invoice_detail/invoice_totals_panel.dart`, `.../invoice_hero_card.dart`, `.../invoice_line_items_card.dart`, `.../invoice_payments_card.dart`, `presentation/widgets/invoice_table.dart`, `presentation/widgets/payment_form.dart`, `presentation/widgets/visit_billing/visit_invoice_review_step.dart`, `.../visit_invoice_summary_panel.dart`, `.../visit_service_selection_*.dart`.
6. Delete `formatMoney` and `_currencySymbol` from `billing_formatting.dart`; replace its call sites with `MoneyFormatter.format(...)` (including `features/service_catalog/presentation/utils/service_price_preview.dart` and `features/patients/presentation/widgets/patient_invoice_card.dart`).
7. Remove the `'USD'` fallbacks in `domain/invoice_detail.dart` line 188 and `domain/invoice_list_item.dart` lines 91–93 only if the RPC contract guarantees `currency`; otherwise keep them but make both files use the same single constant, declared once in `core/money/money_formatter.dart` as `MoneyFormatter.fallbackCurrencyCode`.
8. Verify with `flutter analyze`, then compare the invoice list, invoice detail totals panel, payment dialog, printed receipt, patient profile billing card, and the service catalog price preview: every amount must use the same grouping and the same currency presentation for the same invoice.

---

# H4 — Widgets mutate the ledger through repositories directly, and two write surfaces have no permission gate

**Severity**: High

**Location**
- `frontend/lib/features/billing/presentation/widgets/void_invoice_dialog.dart`
  - imports `features/billing/data/invoice_repository.dart` (line 9)
  - `_VoidInvoiceDialogContentState._submit(BuildContext dialogContext)` — lines 52–94, calling `ref.read(invoiceRepositoryProvider).voidInvoice(...)` (lines 59–65)
- `frontend/lib/features/billing/presentation/widgets/invoice_row_context_menu.dart`
  - imports `features/billing/data/invoice_repository.dart` (line 13)
  - `InvoiceRowContextMenu._voidInvoice(...)` — line 182, `ref.read(invoiceRepositoryProvider).getDetail(invoiceId: row.id)`
  - the "Void invoice" menu entry — line 51, `disabled: !item.status.isVoidable` **only**; no `canVoidInvoice()` check
- `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart` — see **C1**
- Route gate: `frontend/lib/core/auth/auth_route_guard.dart` `billingRouteRedirect` line 260 — every path under `/billing/invoices/` (including `/edit`) is guarded only by `canAccessInvoiceDetail`, which is `canViewInvoices()` (lines 166–175)
- `frontend/lib/features/billing/presentation/pages/invoice_editor_page.dart` — `_issue()` (lines 43–97), `_addService(...)` (99–119), `_removeItem(...)` (121–137); the page never consults `PermissionService`

**Issue**

Two of the three ledger-mutating widgets bypass the provider layer entirely and call `InvoiceRepository` themselves. `VoidInvoiceDialog` is the clearest case: voiding an invoice — a terminal, irreversible status transition — is executed from a `ConsumerState._submit`, with `expectedUpdatedAt` taken from the `InvoiceDetail` that was passed into the dialog constructor and may be arbitrarily stale by the time the operator finishes typing the reason. There is no notifier that owns "the invoice being voided", so nothing refreshes: the caller has to remember to invalidate afterwards, which `InvoiceDetailPage._voidInvoice` does (line 196) and which `InvoiceRowContextMenu._voidInvoice` also does (line 192) — but only because both call sites happened to add it.

Permission gating is inconsistent across the same action. `InvoiceDetailPage` composes `canVoid = widget.view.canVoid && invoice.status.isVoidable` (line 268) and drives a tooltip explaining why the button is disabled. `InvoiceRowContextMenu` checks only the status, so a receptionist without `invoices.void` gets an enabled "Void invoice" item, types a reason, submits, and receives a generic `FORBIDDEN` toast. Similarly, `/billing/invoices/:id/edit` is reachable with only `invoices.view`, and `InvoiceEditorPage` performs no client-side check, so "Issue invoice" is enabled for users who cannot issue.

**Why it is a problem**

Server-side RPCs do enforce the permissions, so this is not a privilege-escalation hole — but it is an architectural inconsistency with real consequences. First, the same business rule ("who may void, and in which statuses") is expressed in three different ways across `invoice_detail_page.dart`, `invoice_detail_tooltip.dart` and `invoice_row_context_menu.dart`, so they drift. Second, because the mutation lives in a widget there is no single place to add stale-revision recovery, in-flight deduplication, or the invalidation that must follow, and one of the two existing refund/void paths already forgets it (`refund_form.dart`, see **H5**). Third, `07-frontend.md` sanctions Billing notifiers calling repositories — it does not sanction widgets doing so, and the widget-level access is what makes the void path untestable.

**Recommended architectural solution**

Introduce a notifier that owns invoice ledger mutations, and one domain-level policy object that answers "which actions are permitted".

- New file `frontend/lib/features/billing/domain/invoice_actions.dart` with `@immutable class InvoiceActionPolicy`, constructed from `InvoiceStatus` plus the five permission booleans, exposing `bool get canEdit`, `canIssue`, `canVoid`, `canRecordPayment`, `canRefund`. This becomes the single definition of the status/permission matrix in `docs/specs/007-billing/invoice-status-cycle.md` § "What is allowed in each status".
- New file `frontend/lib/features/billing/presentation/providers/invoice_ledger_notifier.dart` with `InvoiceLedgerNotifier` (an `AsyncNotifier<void>`-style mutation notifier, family-keyed by `invoiceId`) exposing `Future<void> voidInvoice({required String reason})`, `Future<void> recordPayment({...})` and `Future<void> recordRefund({...})`. It reads `invoiceRepositoryProvider` / `paymentRepositoryProvider`, re-reads `getDetail` immediately before the mutation to obtain a fresh `expectedUpdatedAt`, guards against concurrent submissions with an internal in-flight flag, maps `STALE_INVOICE` to `InvoiceStaleException` (already defined in `presentation/providers/invoice_editor_notifier.dart` — move it to `domain/invoice_stale_exception.dart` so both notifiers can use it), and performs the surface invalidation itself (see **M5**).
- `VoidInvoiceDialog` becomes presentation-only: it collects a reason and returns it via `Navigator.pop(reason)`; the caller passes it to `InvoiceLedgerNotifier.voidInvoice`.
- `InvoiceDetailViewState` gains `InvoiceActionPolicy get actions`, and `InvoiceRowContextMenu` receives the policy (or reads `permissionServiceProvider` and builds one) instead of checking `status.isVoidable` alone.

**Suggested implementation steps**

1. Create `frontend/lib/features/billing/domain/invoice_actions.dart` with `InvoiceActionPolicy`. Move the exact expressions currently in `presentation/pages/invoice_detail_page.dart` lines 266–268 into `canEdit`, `canRecordPayment`, `canVoid`; add `canIssue => status.isDraft && canCreate;` and `canRefund => canRefundPermission && !status.isDraft && !status.isVoided;`.
2. Create `frontend/lib/features/billing/domain/invoice_stale_exception.dart` and move `class InvoiceStaleException` out of `presentation/providers/invoice_editor_notifier.dart`; update that file's imports and the import in `presentation/pages/invoice_editor_page.dart`.
3. Create `frontend/lib/features/billing/presentation/providers/invoice_ledger_notifier.dart` with the three mutation methods described above plus the in-flight guard and the post-mutation invalidation.
4. Edit `presentation/widgets/void_invoice_dialog.dart`: delete the import of `data/invoice_repository.dart`, delete `_submit`'s RPC call and its error handling, and change the dialog to `AppDialog.show<String>` returning the trimmed reason. `VoidInvoiceDialog.show` should return `Future<String?>`.
5. Edit `presentation/pages/invoice_detail_page.dart` `_voidInvoice()`: obtain the reason from the dialog, then call `ref.read(invoiceLedgerProvider(invoice.id).notifier).voidInvoice(reason: reason)` and let the notifier refresh. Replace lines 266–268 with `final actions = widget.view.actions;` and use `actions.canEdit` / `actions.canRecordPayment` / `actions.canVoid`.
6. Edit `presentation/providers/invoice_detail_provider.dart`: add `InvoiceActionPolicy get actions` to `InvoiceDetailViewState`, built from the invoice status and the five existing booleans.
7. Edit `presentation/widgets/invoice_row_context_menu.dart`: delete the import of `data/invoice_repository.dart`; read `permissionServiceProvider` in `build`; construct an `InvoiceActionPolicy` from `row.status` and set `disabled: !policy.canVoid` on the void entry; replace the direct `getDetail` call with the ledger notifier call after collecting the reason.
8. Edit `presentation/pages/invoice_editor_page.dart`: read `permissionServiceProvider`, build an `InvoiceActionPolicy`, and disable "Issue invoice" plus the add/remove affordances when `!policy.canIssue` / `!policy.canEdit`, with a tooltip from `presentation/widgets/invoice_detail/invoice_detail_tooltip.dart`.
9. Edit `frontend/lib/core/auth/auth_route_guard.dart`: add a dedicated branch in `billingRouteRedirect` matching paths ending in `/${AppRoutes.billingInvoiceEditSegment}` and require `PermissionService(auth.context).canCreateInvoices()`, placed *before* the existing generic `startsWith('${AppRoutes.billingInvoices}/')` branch at line 260.
10. Run `rg -n "invoiceRepositoryProvider|paymentRepositoryProvider" frontend/lib/features/billing/presentation/widgets` and confirm zero matches.
11. Verify: as a user with `invoices.view` only, the row menu's "Void invoice" is disabled with an explanatory tooltip and `/billing/invoices/:id/edit` redirects home; as a user with `invoices.void`, voiding from both the detail page and the list row succeeds and both surfaces refresh; double-clicking the void confirm button produces exactly one RPC call.

---

# H5 — No refund UI: `paid` invoices are a dead end in the documented status cycle

**Severity**: High

**Location**
- `frontend/lib/features/billing/presentation/widgets/refund_form.dart` — `class RefundForm` (179 lines, fully implemented, calls `paymentNotifierProvider.recordRefund`); **not referenced by any file**
- `frontend/lib/features/billing/presentation/providers/invoice_detail_provider.dart` — `InvoiceDetailViewState.canRefund` (declared line 29, populated line 51 from `permissions.canRefundPayment()`); **never read by any widget**
- `frontend/lib/features/billing/presentation/pages/invoice_detail_page.dart` — `_InvoiceDetailBodyState` builds `InvoicePaymentsCard` with `canAddPayment` and `onAddPayment` only (lines 365–380); no refund action anywhere
- Gate that closes the trap: `canAddPayment = widget.view.canRecordPayment && !invoice.status.isDraft && !invoice.status.isTerminal` (line 267) — `isTerminal` is true for `paid` (`domain/invoice_status.dart` lines 48–49)
- Backing infrastructure that exists and works: `frontend/lib/features/billing/data/payment_repository.dart` `recordRefund` (lines 47–69) and `frontend/lib/features/billing/presentation/providers/payment_notifier.dart` `recordRefund` (lines 23–29)

**Issue**

`docs/specs/007-billing/invoice-status-cycle.md` is explicit on two points: `void_invoice` is rejected for `paid` invoices (§5, "**Cannot void a `paid` invoice.** Staff must record refunds first"), and `record_refund` is the only transition out of `paid` (§6). The Flutter app implements neither half of that escape hatch in its UI. On the invoice detail page a `paid` invoice offers no payment action (blocked by `isTerminal`), no refund action (never built), and no void action (`isVoidable` is false for `paid`, per `invoice_status.dart` line 45). Every action is disabled.

The pieces are all present — `RefundForm`, `PaymentRepository.recordRefund`, `PaymentNotifier.recordRefund`, and the `canRefund` permission flag — they were simply never wired into a page. `payments.refund` is a seeded permission per `docs/architecture/15-billing.md` § Permissions, so roles exist that are entitled to an action the UI does not expose.

**Why it is a problem**

An invoice that was paid in error, overpaid at the till, or paid against the wrong patient cannot be corrected from the application at all; the only remedy is direct database or RPC access. Because the payments table is append-only (`REVOKE UPDATE, DELETE ON payments`, per `15-billing.md` § RLS Summary), there is no alternative correction mechanism — refunds *are* the correction mechanism. This is a genuine gap in the invoice status machine as documented, and it is the kind of gap that surfaces in production on day one of real cash handling. It also means ~180 lines of tested-looking code (`RefundForm`) and a permission flag are carried as dead weight, misleading anyone who greps for "refund" into believing the feature ships.

**Recommended architectural solution**

Wire the existing refund surface into the invoice detail page behind the existing `canRefund` flag and the status rules from the specification, and route it through the ledger notifier from **H4** so it refreshes like payments do.

- `InvoiceActionPolicy` (created in **H4**) owns the rule: `canRefund` is true when the caller has `payments.refund` **and** the status is one of `issued`, `partially_paid`, `paid` (i.e. not `draft`, not `voided`) — matching the operation matrix in the status-cycle document, which permits refunds in all three of those states.
- `frontend/lib/features/billing/presentation/widgets/invoice_detail/invoice_payments_card.dart` gains `bool canRefund`, `String refundTooltip`, and `VoidCallback? onRefund`, rendered as a secondary action next to the existing "Add payment".
- `RefundForm.onRecorded` changes from `VoidCallback` to `Future<void> Function()` so the caller can await the surface refresh — this is the same signature `PaymentForm` already uses (`presentation/widgets/payment_form.dart` line 22), and it is why `PaymentForm` refreshes correctly while `RefundForm` would not.
- `InvoiceDetailActionTooltips` (`presentation/widgets/invoice_detail/invoice_detail_tooltip.dart`) gains `refundDisabledReason({required bool canRefund, required InvoiceStatus status})` and `refundMessage({String? disabledReason})`, mirroring the existing `addPaymentDisabledReason` / `addPaymentMessage` pair.

**Suggested implementation steps**

1. In `frontend/lib/features/billing/domain/invoice_actions.dart` (from **H4**), confirm `canRefund` is `hasRefundPermission && !status.isDraft && !status.isVoided`.
2. In `frontend/lib/features/billing/presentation/widgets/invoice_detail/invoice_detail_tooltip.dart`, add `refundDisabledReason` and `refundMessage` following the exact shape of the existing `addPaymentDisabledReason` (lines 63–78) and `addPaymentMessage`. Reasons to distinguish: missing permission, `draft` (nothing has been paid yet), `voided` (locked), and "no payments recorded" when `invoice.payments.isEmpty`.
3. In `frontend/lib/features/billing/presentation/widgets/refund_form.dart`, change the `onRecorded` field type from `VoidCallback` to `Future<void> Function()` and `await widget.onRecorded();` in `_submit` after a successful `recordRefund`. Keep the existing `_submitting` guard and `mounted` checks.
4. In `frontend/lib/features/billing/presentation/widgets/invoice_detail/invoice_payments_card.dart`, add the `canRefund` / `refundTooltip` / `onRefund` parameters and render a secondary "Record refund" button beside the existing add-payment action, disabled when `!canRefund`, wrapped in `InvoiceDetailTooltip` with `refundTooltip`.
5. In `frontend/lib/features/billing/presentation/pages/invoice_detail_page.dart`, add `Future<void> _showRefundDialog()` modelled on `_showRecordPaymentDialog` (lines 199–214): `AppDialog.show<void>` with title `'Record refund'`, child `RefundForm(invoice: invoice, onRecorded: () async { Navigator.of(dialogContext).pop(); await ref.read(invoiceLedgerProvider(invoice.id).notifier).refreshSurfaces(); })`. Pass `canRefund: actions.canRefund`, `refundTooltip: InvoiceDetailActionTooltips.refundMessage(...)`, `onRefund: _showRefundDialog` into `InvoicePaymentsCard`.
6. Verify: on a `paid` invoice, "Record refund" is enabled for a user with `payments.refund`; recording a partial refund moves the status to `partially_paid` and re-enables "Add payment"; recording a full refund moves it to `issued` and enables "Void invoice"; on a `voided` invoice the refund action is disabled with the locked-invoice reason; and after each refund the detail page, the invoice list, and the patient profile billing section all show the updated balance.

---

# H6 — Circular presentation-layer coupling between Billing and Visits

**Severity**: High

**Location**
- Billing → Visits presentation/application:
  - `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart` — imports `features/visits/presentation/providers/visit_documentation_notifier.dart` (line 18), `features/visits/presentation/widgets/visit_submitted_dialog.dart` (line 19), `features/visits/application/visit_rpc_messages.dart` (line 13); calls `docNotifier.completeVisit()` (line 89) and `VisitSubmittedDialog.show(...)` (line 125)
  - `frontend/lib/features/billing/presentation/pages/visit_billing_page.dart` — imports `visits/presentation/providers/visit_documentation_notifier.dart` (line 11)
  - `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart` — same import (line 28)
  - `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_service_selection_step.dart` — same import (line 16)
- Visits → Billing presentation/domain:
  - `frontend/lib/features/visits/presentation/widgets/visit_submitted_dialog.dart` — imports `billing/domain/invoice_detail.dart` (line 9) and `billing/domain/visit_billing_models.dart` (line 10)
  - `frontend/lib/features/visits/presentation/widgets/visit_submitted_confirmation_data.dart` — same two imports (lines 3–4)
  - `frontend/lib/features/visits/presentation/widgets/visit_submitted_combined_confirmation.dart` — imports `billing/presentation/widgets/visit_billing/visit_invoice_summary_panel.dart` (line 10)
- Also Billing → Patients presentation: `presentation/pages/invoice_detail_page.dart` line 33 and `visit_invoice_review_step.dart` line 18 import `features/patients/presentation/providers/patient_detail_provider.dart`

**Issue**

Billing and Visits import each other's `presentation/` layers in both directions. Billing's visit-billing wizard drives the *visit* lifecycle (`completeVisit()`), then hands off to a *Visits* dialog; that Visits dialog in turn depends on Billing's `InvoiceDetail` and `VisitBillingInvoicePreview` DTOs, and one of its children renders a Billing widget (`VisitInvoiceSummaryPanel`). There is no acyclic direction to read this in: `visit_billing_flow.dart → visit_submitted_dialog.dart → visit_invoice_summary_panel.dart → billing/domain/...`, while `visit_submitted_dialog.dart` is itself reached from Billing.

The ownership question underneath it is real, not stylistic: **the visit-completion step belongs to Visits, and the invoice-creation step belongs to Billing**, but the combined "finalize this encounter" transaction currently lives in a Billing widget that calls into Visits.

**Why it is a problem**

Neither feature can be understood, modified, or tested without the other, which defeats the purpose of the feature-first layout in `07-frontend.md`. Practically: changing `VisitSubmittedDialog`'s constructor is a Billing change; changing `VisitBillingInvoicePreview` is a Visits change. Cross-`presentation/` imports are the worst kind of coupling because presentation types change most often and carry widget/BuildContext concerns with them. It also hides the C1 defect — the reason "visit completed but invoice failed" has no sensible owner is precisely that the transaction spans two features with no single coordinator.

Note that the *domain*-only direction (Visits importing `billing/domain/invoice_detail.dart`) is acceptable and should be preserved; the problems are the presentation↔presentation edges and the misplaced orchestration.

**Recommended architectural solution**

Keep exactly one direction for presentation dependencies (Visits → Billing domain, and Billing → shared confirmation contract), and give the cross-feature transaction a neutral coordinator.

- Move the shared confirmation payload out of Visits' widget folder into a feature-neutral location: new file `frontend/lib/features/visits/domain/visit_submission_confirmation.dart` holding the data currently in `features/visits/presentation/widgets/visit_submitted_confirmation_data.dart`. It may reference `billing/domain/invoice_detail.dart` (domain→domain is fine).
- Keep `VisitSubmittedDialog` in Visits, but have it accept the neutral `VisitSubmissionConfirmation` value object and an injected `Widget? invoiceSummary` slot instead of importing `visit_invoice_summary_panel.dart` itself. The Billing caller supplies the panel. This removes the Visits → Billing *presentation* edge.
- Move the two-feature transaction into the coordinator created by **C1**: `frontend/lib/features/billing/application/visit_invoice_finalization_service.dart` does the invoice half, and `VisitBillingFlowNotifier.finalize()` sequences `completeVisit()` and the invoice half, returning `VisitFinalizeOutcome`. The Visits dependency then narrows to a single provider read in one notifier rather than being spread across four Billing widgets.
- Replace the direct `patientDetailProvider` reads with the patient fields already present on the payloads: `InvoiceDetail` already carries `patientDisplayName`, `patientMrn`, `patientPhone`, `patientDateOfBirth` (`domain/invoice_detail.dart` lines 115–118). Only fall back to `patientDetailProvider` where a field is genuinely absent.

**Suggested implementation steps**

1. Create `frontend/lib/features/visits/domain/visit_submission_confirmation.dart`; move the class(es) from `features/visits/presentation/widgets/visit_submitted_confirmation_data.dart` into it unchanged, then delete the old file and update its importers.
2. Edit `features/visits/presentation/widgets/visit_submitted_combined_confirmation.dart`: delete the import of `billing/presentation/widgets/visit_billing/visit_invoice_summary_panel.dart`; add a `final Widget? invoiceSummary;` constructor parameter and render it where the panel used to be.
3. Edit `features/visits/presentation/widgets/visit_submitted_dialog.dart`: change `show(...)` to take a `VisitSubmissionConfirmation` plus `Widget? invoiceSummary`, and forward `invoiceSummary` down to `VisitSubmittedCombinedConfirmation`. Keep the `billing/domain/*` imports.
4. Edit `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart`: at the `VisitSubmittedDialog.show(...)` call site, construct the `VisitSubmissionConfirmation` and pass `invoiceSummary: VisitInvoiceSummaryPanel(...)`. After **C1** this call site is the only remaining Visits dependency in this file besides the notifier read.
5. Move the `visitDocumentationProvider` reads out of `visit_invoice_review_step.dart` (line 28 import) and `visit_service_selection_step.dart` (line 16 import): have `VisitBillingPage` (`presentation/pages/visit_billing_page.dart`) read the visit once and pass the needed values (patient id, patient display name) down as constructor parameters to the two step widgets. Only `visit_billing_page.dart` and `visit_billing_flow_notifier.dart` should import anything from `features/visits/`.
6. In `presentation/pages/invoice_detail_page.dart`, keep `_resolvePatientPhone`'s preference for `invoice.patientPhone` but drop the `patientDetailProvider` fallback if the `get_invoice_detail` RPC reliably returns `patient.phone` (the repository comment at `data/invoice_repository.dart` lines 195–198 says it does when present); if the fallback must stay, leave it and accept this single domain-adjacent dependency.
7. Run `rg -n "features/visits/presentation|features/patients/presentation" frontend/lib/features/billing` and confirm the only remaining matches are in `presentation/pages/visit_billing_page.dart` and `presentation/providers/visit_billing_flow_notifier.dart`. Run `rg -n "features/billing/presentation" frontend/lib/features/visits` and confirm zero matches.
8. Verify by completing a visit end-to-end from the encounter workspace through `/billing/visits/:visitId`: the service selection step, the review step, and the submitted-confirmation dialog (with its embedded invoice summary) must all behave exactly as before.

---

# H7 — 1210-line god file hosting two distinct flows, document layout, and invoice→preview mapping

**Severity**: High

**Location**
- `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart` (1210 lines). Distinct responsibilities in one file:
  - `VisitInvoiceReviewStep` + `_VisitInvoiceReviewStepState` (lines 31–424) — the *editable* wizard step: two animation controllers, permission read, responsive 1024px breakpoint layout, footer wiring
  - `VisitInvoiceReadOnlyReview` — the *read-only* document used by a completely different route, `/billing/invoices/:id/review` via `presentation/pages/invoice_review_page.dart` line 60
  - `_InvoiceDocumentCard` (lines 474+) — the printable invoice document: header, patient block, line table, totals, issued-date formatting with its own `DateFormat('d MMM yyyy')`
  - `_InvoiceLineTable`, `_TotalRow` — table rendering
  - `_PerforatedEdge` + `_PerforatedEdgePainter` (≈ lines 716–754) — a custom painter
  - `_DiscountSidebar`, `_ReadOnlyDiscountSidebar`, `_DiscountInfoCard` — discount entry UI, including the validation rule `_fixedDiscountExceedsSubtotal` (≈ lines 930–933)
  - `_InvoiceReviewFooter` — action bar
  - Mapping helpers `_linesFromInvoiceItems` (426–438), `_discountFromInvoice` (440–462), `_totalsFromInvoice` (464–472) — server DTO → wizard preview model conversion

**Issue**

One file serves two unrelated entry points (a step inside the post-visit wizard, and a standalone read-only invoice page), owns the invoice document's visual layout, owns a custom painter, owns the discount input UI and its validation, and owns the `InvoiceDetail` → `VisitBillingInvoicePreview` mapping. It is the largest file in the feature by a factor of 2.4 and is imported by both `visit_billing_flow.dart` (line 16) and `invoice_review_page.dart` (line 10).

The mapping helpers are the most consequential part: `_linesFromInvoiceItems` sets `serviceId: item.id` — an `invoice_items.id` written into a field named `serviceId` that everywhere else holds a catalog `services.id`. It is harmless today because the read-only path never sends that value back, but it is a live trap for anyone who later reuses those lines for a mutation. `_totalsFromInvoice` is the insurance-omitting double arithmetic reported in **C3**.

**Why it is a problem**

Any change to the editable wizard step risks the standalone review page and vice versa, because they share private widgets in a single 1200-line scope. The file cannot be reviewed in a normal diff, the document layout cannot be reused by the PDF builder (which re-implements it in `receipt_print_preview.dart`, see **M6**), and the discount validation rule is buried in a private method of a private widget where no test can reach it. This is the file where the `serviceId`/`item.id` conflation could hide indefinitely.

**Recommended architectural solution**

Split by responsibility into six files under `presentation/widgets/visit_billing/`, keeping every widget's rendered output byte-identical. This is a pure mechanical extraction — no logic changes beyond those mandated by **C3** and **H1**.

| New file | Moves |
| -------- | ----- |
| `visit_invoice_document_card.dart` | `_InvoiceDocumentCard` → `VisitInvoiceDocumentCard`; `_InvoiceLineTable` → `VisitInvoiceLineTable`; `_TotalRow` |
| `visit_invoice_discount_sidebar.dart` | `_DiscountSidebar` → `VisitInvoiceDiscountSidebar`; `_ReadOnlyDiscountSidebar`; `_DiscountInfoCard`; `_fixedDiscountExceedsSubtotal` |
| `visit_invoice_read_only_review.dart` | `VisitInvoiceReadOnlyReview` (public already) |
| `visit_invoice_review_footer.dart` | `_InvoiceReviewFooter` → `VisitInvoiceReviewFooter` |
| `visit_perforated_edge.dart` | `_PerforatedEdge`, `_PerforatedEdgePainter` → `VisitPerforatedEdge` (or delete and reuse the existing `presentation/widgets/invoice_perforation_divider.dart`) |
| `visit_invoice_review_step.dart` (remaining) | only `VisitInvoiceReviewStep` + its state, ~250 lines |

The three mapping helpers do **not** belong in `presentation/`. Move them to a new `frontend/lib/features/billing/domain/visit_billing_mapping.dart` as `VisitBillingMapping.linesFromInvoice(InvoiceDetail)` and `VisitBillingMapping.discountFromInvoice(InvoiceDetail)`; delete `_totalsFromInvoice` outright per **C3**/**H1** and read `invoice.originalDue` / `invoice.balance` instead.

**Suggested implementation steps**

1. Create `frontend/lib/features/billing/domain/visit_billing_mapping.dart` with `abstract final class VisitBillingMapping` containing `linesFromInvoice` and `discountFromInvoice`, moved from lines 426–462. In `linesFromInvoice`, change `serviceId: item.id` to `serviceId: ''` and add a one-line comment stating that invoice items do not carry the originating catalog service id — or, preferably, add a `String? serviceId` field to `domain/invoice_item.dart` if `get_invoice_detail` returns it, and map the real value.
2. Create `visit_perforated_edge.dart` and move `_PerforatedEdge` / `_PerforatedEdgePainter`, renaming to `VisitPerforatedEdge` / `VisitPerforatedEdgePainter`.
3. Create `visit_invoice_document_card.dart` and move `_InvoiceDocumentCard`, `_InvoiceLineTable`, `_TotalRow`, renaming the first two to public names. Keep the constructor parameter list identical. Import `visit_perforated_edge.dart`.
4. Create `visit_invoice_discount_sidebar.dart` and move `_DiscountSidebar`, `_ReadOnlyDiscountSidebar`, `_DiscountInfoCard` and the `_fixedDiscountExceedsSubtotal` validation, renaming the first to `VisitInvoiceDiscountSidebar`.
5. Create `visit_invoice_review_footer.dart` and move `_InvoiceReviewFooter` → `VisitInvoiceReviewFooter`.
6. Create `visit_invoice_read_only_review.dart` and move `VisitInvoiceReadOnlyReview`; it imports the document card, the read-only sidebar, and `VisitBillingMapping`.
7. Trim `visit_invoice_review_step.dart` to `VisitInvoiceReviewStep` + `_VisitInvoiceReviewStepState` only; add imports for the five new files; remove now-unused imports (`intl`, `app_number_input.dart`, `app_radio_group.dart`, `invoice_item.dart`, `invoice_status_badge.dart`, `app_avatar.dart` will mostly migrate to the extracted files).
8. Update `frontend/lib/features/billing/presentation/pages/invoice_review_page.dart` line 10 to import `visit_invoice_read_only_review.dart` instead of `visit_invoice_review_step.dart`.
9. Run `flutter analyze` and confirm zero new diagnostics and no unused imports. Then visually diff both surfaces against the pre-refactor build: the wizard review step at `/billing/visits/:visitId` (with and without `invoices.apply_discount`) and the read-only document at `/billing/invoices/:id/review`. Layout must be pixel-identical.

---

# M1 — Large unreachable write surface behind placeholder routes

**Severity**: Medium

**Location**
- `frontend/lib/features/billing/presentation/providers/invoice_editor_notifier.dart` — the following `InvoiceEditorNotifier` members have **no call site anywhere in `frontend/lib`**: `reload()` (75–80), `updateItemQuantity(...)` (117–131), `addItem(...)` (133–147), `updateItem(...)` (149–164), `discardDraft()` (184–191), `applyLineDiscount(...)` (193–206), `applyInvoiceDiscount(...)` (208–217), `setInsuranceCoverage(...)` (219–231); plus the state getters `hasLineDiscounts` (27–28), `hasInvoiceDiscount` (30), `activeDiscountScope` (32–40)
- `frontend/lib/features/billing/domain/discount_scope.dart` — `DiscountScope` is referenced only by the unused `activeDiscountScope`
- `frontend/lib/features/billing/presentation/providers/insurance_providers_notifier.dart` — `insuranceProvidersProvider` and `activeInsuranceProvidersProvider` have no consumer
- `frontend/lib/features/billing/data/insurance_provider_repository.dart` — reachable only from `app/shell/dev/dev_clinic_seed_service.dart`
- `frontend/lib/features/billing/presentation/providers/billing_settings_notifier.dart` — `BillingSettingsNotifier.updateAllowPartialPayments` has no consumer; `billingSettingsProvider` is read only by `presentation/widgets/payment_form.dart` line 35
- Routes that would host these surfaces, both wired to `shellPlaceholderPage`: `frontend/lib/app/router.dart` line 152 (`AppRoutes.billingInsuranceProviders` = `/billing/insurance-providers`) and line 153 (`AppRoutes.settingsBilling` = `/settings/billing`)

**Issue**

Roughly a third of Billing's mutation surface is implemented and unreachable. Three whole capabilities described as business rules in `docs/architecture/15-billing.md` have no UI:
- **Discounts on an existing draft** — line-level and invoice-level (`15-billing.md` § Key Business Rules, "mutually exclusive on draft invoices"). The only discount path that ships is the invoice-level discount inside the visit-billing wizard (`visit_billing_flow.dart` line 197). `InvoiceEditorPage` has no discount UI at all, so the mutual-exclusivity rule that `activeDiscountScope` was written to enforce is never evaluated.
- **Insurance coverage** — `setInsuranceCoverage` and the whole insurance provider catalog are unreachable, though `InvoiceTotalsPanel` renders `insuranceCoveredAmount` and `insuranceProviderName` when present (only dev-seeded data can produce them).
- **Partial payments toggle** — `update_billing_settings` is exposed by `BillingSettingsNotifier` but `/settings/billing` is a placeholder, so `allowPartialPayments` can never be changed from the app. `PaymentForm._amountLocked` then enforces "full balance required" based on a setting no administrator can turn on.

`docs/architecture/15-billing.md` § Frontend (Current) simultaneously claims "Frontend presentation **Complete**", "No `presentation/` layer yet", and lists "Insurance provider management" and "Settings → Billing (partial payments toggle)" as implemented surfaces. This is documentation drift adjacent to `ARCHITECTURAL_FLAWS.md` **H1** (which is now stale in the opposite direction — it says no presentation layer exists at all).

**Why it is a problem**

Dead mutation code is worse than missing code: it reads as shipped, so a reviewer verifying "can we apply a discount to a draft?" finds `applyInvoiceDiscount` and concludes yes. It also rots — `updateItemQuantity` and `addItem` carry `expectedUpdatedAt` protocol details that will silently diverge from `InvoiceRepository` as the protocol evolves, and nothing will catch it because nothing calls them. The concrete operational consequence is that the partial-payment rule is stuck at its default and insured invoices cannot be produced by real users.

**Recommended architectural solution**

Decide per capability, and record the decision. Do not leave the current ambiguous middle state.

- **Keep and wire** the draft-editor discount and insurance surfaces, because `InvoiceEditorPage` already exists and is the natural host: add a discount section (radio for scope, kind, value) and an insurance section (provider select + covered amount) to `frontend/lib/features/billing/presentation/pages/invoice_editor_page.dart`, driven by the existing notifier methods and gated by `InvoiceActionPolicy.canApplyDiscount` from **H4**. `activeDiscountScope` then becomes live and enforces mutual exclusivity client-side before the RPC rejects with `DISCOUNT_SCOPE_CONFLICT`.
- **Keep and wire** the billing settings toggle: replace the `shellPlaceholderPage` at `router.dart` line 153 with a small `BillingSettingsPage` under `frontend/lib/features/billing/presentation/pages/billing_settings_page.dart` containing one switch bound to `BillingSettingsNotifier.updateAllowPartialPayments`, gated on `PermissionService.canManageBillingSettings()`.
- **Delete or defer explicitly** the insurance provider catalog: either build `frontend/lib/features/billing/presentation/pages/insurance_providers_page.dart` at `router.dart` line 152, or delete `presentation/providers/insurance_providers_notifier.dart` and leave only `data/insurance_provider_repository.dart` (still used by the dev seeder) with a comment naming the roadmap item.
- Then correct `docs/architecture/15-billing.md` § Frontend (Current) and retire the stale `ARCHITECTURAL_FLAWS.md` **H1** row.

**Suggested implementation steps**

1. Create `frontend/lib/features/billing/presentation/pages/billing_settings_page.dart`: a `ConsumerWidget` that watches `billingSettingsProvider`, renders one labelled switch for `allowPartialPayments`, calls `ref.read(billingSettingsProvider.notifier).updateAllowPartialPayments(value)`, and shows a permission-denied empty state when `!PermissionService(...).canManageBillingSettings()`.
2. In `frontend/lib/app/router.dart` line 153, replace `builder: shellPlaceholderPage` for `AppRoutes.settingsBilling` with `builder: (context, state) => const BillingSettingsPage()` and add the import.
3. In `frontend/lib/core/auth/auth_route_guard.dart` `canAccessBillingSettings` (lines 184–190), tighten the check from `canViewInvoices() || canRecordPayment()` to `canManageBillingSettings()`, matching `15-billing.md` § Permissions which assigns `settings.billing.manage` to this surface.
4. In `frontend/lib/features/billing/presentation/pages/invoice_editor_page.dart`, add a discount panel and an insurance panel below the line-items list. Wire them to `applyInvoiceDiscount`, `applyLineDiscount`, and `setInsuranceCoverage`; populate the provider dropdown from `activeInsuranceProvidersProvider`; disable the invoice-level control when `state.activeDiscountScope == DiscountScope.line` and vice versa; surface `DISCOUNT_SCOPE_CONFLICT` through `billingMessageForRpc`.
5. Add a "Discard draft" secondary action to the same page bound to `discardDraft()`, navigating back to `/billing/invoices` on success.
6. Decide on the insurance provider catalog. If deferring: delete `presentation/providers/insurance_providers_notifier.dart`, and if step 4 needs the provider list, inline a `FutureProvider` in the editor page instead.
7. Delete any member still unused after steps 4–6 (`reload`, `addItem`, `updateItem`, `updateItemQuantity` if the editor uses `addItemFromService`/`removeItem` only).
8. Update `docs/architecture/15-billing.md` § Frontend (Current) to describe the real state, and remove the contradictory "No `presentation/` layer yet" sentence. Mark `ARCHITECTURAL_FLAWS.md` row **H1** as resolved.
9. Verify: as an administrator, toggle partial payments off and confirm `PaymentForm` locks the amount to the full balance; toggle it on and confirm a partial amount is accepted; apply a 10% invoice discount to a draft, then attempt a line discount and confirm the UI blocks it before the RPC does; set insurance coverage and confirm the detail page's totals panel shows the provider name and covered amount.

---

# M2 — N+1 `get_invoice_detail` fan-out inside a presentation provider, with errors silently swallowed

**Severity**: Medium

**Location**
- `frontend/lib/features/billing/presentation/providers/invoice_detail_provider.dart`
  - `patientInvoicesProvider` — lines 72–86, specifically `await Future.wait(page.items.map((item) => _enrichInvoicePayments(repo, item)))` (line 83)
  - `_enrichInvoicePayments(InvoiceRepository repo, InvoiceListItem item)` — lines 88–107; calls `repo.getDetail(invoiceId: item.id)` (line 99) and swallows every failure with `on Object { return item; }` (lines 104–106)
- Consumer: `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart` line 11 (imports this Billing provider) and `frontend/lib/features/patients/presentation/widgets/patient_invoice_card.dart`

**Issue**

`list_patient_invoices` returns summary rows. To render payment chips on the patient profile, the provider fires one additional `get_invoice_detail` RPC per row that has a non-zero `paidAmount` or `insuranceCoveredAmount` and an empty `payments` array — concurrently, via `Future.wait`, with no concurrency cap. For a patient with 30 invoices this is up to 31 RPCs in one burst on a clinic LAN. Two further problems compound it: the enrichment is a *data-shaping* concern implemented in a `presentation/` provider, and `on Object { return item; }` discards every error, so a failure is indistinguishable from "this invoice genuinely has no payments" — the card silently renders as unpaid.

**Why it is a problem**

Per `07-frontend.md`'s layer table, response shaping belongs in `data/`; a presentation provider composing a list read with N detail reads means the "what does a patient invoice row look like" contract has no single owner, and the Patients feature depends on a Billing *presentation* provider to get it. The unbounded fan-out is a real performance and LAN-load issue for long-tenured patients, and the blanket catch converts transient network failures into wrong financial information on screen with no indication that anything went wrong.

**Recommended architectural solution**

Move the composition into the data layer, bound the concurrency, and stop hiding failures.

- Add `Future<InvoiceListPageResult> listPatientInvoicesWithPayments({required String patientId, int limit = 50, int offset = 0})` to `frontend/lib/features/billing/data/invoice_repository.dart`. It performs the list read, then the enrichment, sequentially in batches of at most 5, and lets `RpcFailure` propagate.
- `patientInvoicesProvider` becomes a thin call to that method plus the existing `AuthRouteGuard.canAccessInvoiceList` short-circuit, so it holds no data-shaping logic.
- Preferred longer-term fix, to be recorded as a backend follow-up rather than done here: have `list_patient_invoices` include the payment rows so the enrichment disappears entirely. Note it in `docs/architecture/15-billing.md` § RPC Inventory.

**Suggested implementation steps**

1. In `frontend/lib/features/billing/data/invoice_repository.dart`, add `listPatientInvoicesWithPayments(...)`. Move the body of `_enrichInvoicePayments` into a private `Future<InvoiceListItem> _withPayments(InvoiceListItem item)` on the repository, keeping the two early-return guards (`item.payments.isNotEmpty || item.status == InvoiceStatus.draft`, and `paidAmount.isZero && insuranceCoveredAmount.isZero`) but removing the `on Object` catch. Import `domain/invoice_status.dart`.
2. Implement the batching: iterate the items in chunks of 5 and `Future.wait` each chunk, rather than the whole page at once.
3. In `frontend/lib/features/billing/presentation/providers/invoice_detail_provider.dart`, replace the body of `patientInvoicesProvider` with the guard plus `return ref.read(invoiceRepositoryProvider).listPatientInvoicesWithPayments(patientId: patientId);`. Delete `_enrichInvoicePayments` and the now-unused `domain/invoice_status.dart` import if nothing else in the file needs it.
4. In `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart`, ensure the `AsyncValue.error` branch of the billing section renders a retry affordance, since errors now surface instead of being swallowed.
5. Verify: open a patient with several paid invoices and confirm the payment chips still render; check the RPC log domain output (`billing.invoices`) to confirm the detail calls arrive in batches rather than all at once; then simulate a failure on one enrichment call and confirm the patient profile's billing section shows an error state with retry rather than silently showing the invoice as unpaid.

---

# M3 — Client-side sort applied to one server page produces globally wrong ordering

**Severity**: Medium

**Location**
- `frontend/lib/features/billing/presentation/models/invoice_sort_key.dart` — `sortInvoiceListItemsClientSide(List<InvoiceListItem> items, InvoiceListFilters filters)` (lines 114–138), carrying `TODO(invoices-page-implementation-plan §6)` at lines 112–113
- `frontend/lib/features/billing/presentation/providers/invoice_list_notifier.dart` — `InvoiceListNotifier._load(...)` line 125, applied *after* the paged read at lines 112–118
- `frontend/lib/features/billing/presentation/models/invoice_list_filters.dart` — `toRpcFilters(...)` lines 97–100 send `sort_field` and `sort_direction`
- `frontend/lib/features/billing/data/invoice_repository.dart` — `listInvoices(...)` lines 207–217, whose comment states server-side honouring is "not yet implemented"
- Pagination: `InvoiceListFilters.pageSize = 10` (line 18), `offset` (line 32); `estimatedTotal = filters.offset + items.length + (page.hasMore ? 1 : 0)` (`invoice_list_notifier.dart` lines 127–128)

**Issue**

The server paginates with `LIMIT 10 OFFSET n` in its own (unsorted-by-request) order, then the client re-sorts only the ten rows it received. Sorting by "Remaining (highest)" therefore returns the highest-balance invoices *within page 1*, not the highest-balance invoices overall — and paging to page 2 reshuffles a different arbitrary ten. The UI presents this as a global sort: `InvoiceSortKey.options` (lines 93–100) offers six global-sounding labels and `InvoiceListControls` renders them as a standard sort control.

`estimatedTotal` compounds the impression of a coherent dataset by reporting a footer count derived from offset plus loaded plus a `hasMore` hint.

**Why it is a problem**

This is a correctness defect from the operator's point of view: "show me the invoices with the largest outstanding balance" is a core receptionist task, and the answer the UI gives is wrong whenever there is more than one page. It is also latent architectural debt in the wrong layer — a compensation for a missing backend capability is implemented in `presentation/models/`, so the presentation layer now owns a sorting semantic that belongs to `list_invoices`. The existing `TODO` acknowledges the situation but does not prevent the wrong result from being shown today. Note this is partially known: the invoice list implementation plan §6 referenced by the TODO tracks it, so treat this as an unresolved documented gap with concrete guidance added rather than a new discovery.

**Recommended architectural solution**

Stop presenting a global sort the backend cannot deliver, and remove the client-side compensation from the presentation layer once the RPC honours the parameters.

Two steps, in order:

1. **Immediate, frontend-only.** Delete `sortInvoiceListItemsClientSide` and its call site. Restrict the sort control to the ordering `list_invoices` actually guarantees — created-at descending — by reducing `InvoiceSortKey.options` to the two date options, and keep sending `sort_field`/`sort_direction` so the wiring is ready. This trades a feature for correctness, which is the right trade for money.
2. **Backend follow-up, tracked separately.** Once `list_invoices` orders by `sort_field`/`sort_direction` server-side, restore the four balance/subtotal options. No frontend change beyond re-adding the option entries is then required, because `toRpcFilters` already forwards them.

If removing the options is judged unacceptable before the backend lands, the minimum honest interim is to keep them but label them explicitly as page-scoped in `InvoiceSortKey.label` (for example "Remaining (highest, this page)") so the UI does not assert something false.

**Suggested implementation steps**

1. In `frontend/lib/features/billing/presentation/providers/invoice_list_notifier.dart`, delete line 125 (`final items = sortInvoiceListItemsClientSide(page.items, filters);`) and use `page.items` directly in the `InvoiceListUiState` construction; delete the now-unused import of `presentation/models/invoice_sort_key.dart` if `InvoiceSortField` is not otherwise referenced in the file.
2. In `frontend/lib/features/billing/presentation/models/invoice_sort_key.dart`, delete `sortInvoiceListItemsClientSide` and its TODO comment. Keep `InvoiceSortField`, `InvoiceSortKey`, `backendSort`, `tryParse`, `fromFilters` and `InvoiceSortDirectionWire` — they are the correct wire mapping.
3. In the same file, reduce `InvoiceSortKey.options` (lines 93–100) to the `date-desc` and `date-asc` entries. Leave the enum values in place so `fromFilters` still round-trips if a stored filter references one.
4. Add a short comment above `options` naming the backend work item required to restore the balance and subtotal entries, and referencing `data/invoice_repository.dart` `listInvoices`.
5. In `frontend/lib/features/billing/data/invoice_repository.dart` lines 208–209, update the comment to say the client no longer compensates and that unsupported sort fields will simply be ignored by the server.
6. Verify: with more than 10 invoices in the branch, confirm the sort control offers only the two date orderings, that page 1 → page 2 → page 1 produces a stable, non-reshuffling sequence, and that the footer count still increments as expected.

---

# M4 — Partial-payment business rule implemented in a widget and evaluated with `ref.watch` from a submit path

**Severity**: Medium

**Location**
- `frontend/lib/features/billing/presentation/widgets/payment_form.dart`
  - `_PaymentFormState._amountLocked` — lines 34–38: `final settings = ref.watch(billingSettingsProvider).value; final isPatientTender = _method != PaymentMethod.insuranceSettlement; return settings != null && !settings.allowPartialPayments && isPatientTender;`
  - `_PaymentFormState._resolvedAmount` — line 40: `_amountLocked ? widget.invoice.balance.wireValue : (_amount ?? '')`
  - `_PaymentFormState._submit()` — line 47 reads `_resolvedAmount`, which transitively calls `_amountLocked` and therefore `ref.watch`, outside of `build`
  - UI consequences: `helperText` at line 151, `disabled` at line 155, `initialValue` at line 156

**Issue**

The rule encoded here is a documented domain rule, not a widget concern. `docs/specs/007-billing/invoice-status-cycle.md` §3 states it precisely: "If org setting **Allow partial payments** is disabled, patient-tender methods (`cash`, `card`, `bank_transfer`) must pay the **full** balance; `insurance_settlement` is exempt from this rule." That sentence is implemented as a private getter on a `ConsumerState`, expressed as the negation `_method != PaymentMethod.insuranceSettlement` rather than as an enumeration of patient-tender methods — so adding a fifth payment method silently classifies it as patient tender.

Two secondary issues follow from its placement:

- `_amountLocked` uses `ref.watch`, and `_submit` reaches it through `_resolvedAmount`. `ref.watch` on a `ConsumerState` is intended for `build` only; calling it from an event handler is at best a subscription established at an undefined point in the lifecycle, and in debug builds Riverpod asserts against listening outside of build. The submit path should be reading a value, not establishing a dependency.
- When `billingSettingsProvider` has not yet resolved, `settings` is `null` and `_amountLocked` returns `false`, so the form permits a partial amount that the RPC will then reject with `PARTIAL_PAYMENTS_DISABLED`. The failure mode is a confusing late error rather than a locked field.

**Why it is a problem**

The rule cannot be unit-tested, cannot be reused by any other payment surface, and disagrees with its own specification in shape (negation instead of an explicit tender set). Because it is also the *only* consumer of `billingSettingsProvider` (see **M1**), the entire partial-payments feature is expressed in one private getter of one widget. And the `ref.watch`-from-submit pattern is the kind of thing that works until a Riverpod upgrade tightens the assertion.

**Recommended architectural solution**

Move the rule to the domain layer, make the tender classification explicit, and have the widget read settings rather than watch them at submit time.

- In `frontend/lib/features/billing/domain/payment_method.dart`, add `bool get isPatientTender => this == PaymentMethod.cash || this == PaymentMethod.card || this == PaymentMethod.bankTransfer;` — an explicit enumeration, so a new method must opt in.
- New file `frontend/lib/features/billing/domain/payment_policy.dart` with `abstract final class PaymentPolicy` exposing `bool requiresFullBalance({required PaymentMethod method, required bool allowPartialPayments}) => method.isPatientTender && !allowPartialPayments;`.
- `PaymentForm` obtains `allowPartialPayments` from `ref.watch(billingSettingsProvider)` **in `build` only**, stores the resolved boolean in a local, passes it to `PaymentPolicy.requiresFullBalance`, and keeps the resulting `amountLocked` boolean in `State` so `_submit` reads a field rather than calling `ref.watch`.
- While `billingSettingsProvider` is loading, disable the submit button rather than defaulting to "partial allowed", so the form never sends an amount the server will reject on this rule.

**Suggested implementation steps**

1. In `frontend/lib/features/billing/domain/payment_method.dart`, add the `isPatientTender` getter enumerating `cash`, `card`, `bankTransfer`.
2. Create `frontend/lib/features/billing/domain/payment_policy.dart` with `PaymentPolicy.requiresFullBalance({required PaymentMethod method, required bool allowPartialPayments})`.
3. In `frontend/lib/features/billing/presentation/widgets/payment_form.dart`: delete the `_amountLocked` getter and the `_resolvedAmount` getter. Add `var _amountLocked = false;` and `var _settingsLoaded = false;` as `State` fields.
4. At the top of `build`, add `final settingsAsync = ref.watch(billingSettingsProvider);` then compute `_settingsLoaded = settingsAsync.hasValue;` and `_amountLocked = settingsAsync.hasValue && PaymentPolicy.requiresFullBalance(method: _method, allowPartialPayments: settingsAsync.requireValue.allowPartialPayments);`. Assign these before they are used further down `build`; do not call `setState` here.
5. In `_submit`, compute the amount as `_amountLocked ? widget.invoice.balance.wireValue : (_amount ?? '')` using the field, with no provider access.
6. Change the submit button's `onPressed` guard (line 178) to also require `_settingsLoaded`, and its `loading` to `_submitting || !_settingsLoaded`.
7. Because `_method` changes must recompute the lock, confirm the existing `setState(() => _method = method)` in the method `AppSelect.onChanged` (lines 137–142) still triggers a rebuild — it does; no further change is needed. The existing `ValueKey('${_method.name}-${widget.invoice.balance.wireValue}')` on `AppMoneyField` (line 153) already resets the field when the lock changes.
8. Verify: with partial payments disabled, select `Cash` and confirm the amount is locked to the full balance with the helper text shown; switch to `Insurance settlement` and confirm the amount becomes editable; enable partial payments (needs the settings page from **M1**) and confirm `Cash` becomes editable; open the dialog on a slow connection and confirm the submit button stays disabled until settings load rather than allowing a rejected partial payment.

---

# M5 — Cross-surface cache invalidation is a free function taking `WidgetRef`, callable only from widgets and easy to omit

**Severity**: Medium

**Location**
- `frontend/lib/features/billing/presentation/providers/invoice_detail_provider.dart` — `Future<void> refreshInvoiceBillingSurfaces(WidgetRef ref, {required String invoiceId, required String patientId})`, lines 56–69; invalidates `invoiceDetailViewProvider(invoiceId)`, `patientInvoicesProvider(patientId)` and `invoiceListProvider`, then awaits the detail future and `invoiceListProvider.notifier.reload()`
- Call sites: `presentation/pages/invoice_detail_page.dart` line 196 (after void) and line 209 (after payment); `presentation/widgets/invoice_row_context_menu.dart` line 192 (after void from the list)
- Missing call site: `presentation/widgets/refund_form.dart` line 85 calls a plain `VoidCallback onRecorded` and never refreshes (see **H5**)
- Note the file's own dependency direction: a `presentation/providers/` file imports `flutter_riverpod`'s `WidgetRef`, a widget-layer type

**Issue**

The knowledge "a ledger mutation must refresh these three surfaces" is a top-level function parameterised by `WidgetRef`. Because it takes `WidgetRef` rather than `Ref`, it can only be called from a widget or a `ConsumerState` — never from a notifier, which is where mutations should live. So the invalidation is necessarily duplicated at every widget-level mutation site, and it is duplicated inconsistently: two void paths and one payment path call it, while the refund path (`RefundForm`) does not, which is exactly the class of omission this shape invites.

There is also a subtle ordering dependency: the function invalidates all three providers and then awaits two of them. `patientInvoicesProvider` is invalidated but not awaited, which is fine for an autoDispose family that will rebuild on next watch, but it means the function's contract ("everything is fresh when this returns") is only two-thirds true.

**Why it is a problem**

Refresh-after-mutate is a cache-coherence rule of the Billing feature; encoding it as a helper that only widgets can invoke guarantees it will be forgotten by at least one call site, and it already has been. It also inverts the layer dependency described in `07-frontend.md`: a file under `presentation/providers/` should not need a widget-layer handle. Practically, when a new billing mutation surface is added (refunds per **H5**, discounts and insurance per **M1**), each one has to remember this call, and there is no compile-time or review-time signal when it is missed.

**Recommended architectural solution**

Make refreshing a responsibility of the notifier that performs the mutation, so it cannot be skipped, and express it in terms of `Ref` rather than `WidgetRef`.

- Move the invalidation into `InvoiceLedgerNotifier` (created in **H4**) as a private `Future<void> _refreshSurfaces({required String invoiceId, required String patientId})` that uses the notifier's own `ref` (a `Ref`, not `WidgetRef`). Every mutation method calls it in its success path, so `voidInvoice`, `recordPayment` and `recordRefund` are coherent by construction.
- Keep one public entry point for the rare case where a widget genuinely needs to force a refresh without mutating: expose `Future<void> refreshSurfaces()` on the notifier and delete the free function.
- Add `patientInvoicesProvider(patientId)` to the awaited set so the returned future actually means "all three surfaces are current", which matters because `InvoiceDetailPage`'s dialogs pop before awaiting.

**Suggested implementation steps**

1. In `frontend/lib/features/billing/presentation/providers/invoice_ledger_notifier.dart` (from **H4**), add `Future<void> _refreshSurfaces({required String invoiceId, required String patientId})` containing the body of the current `refreshInvoiceBillingSurfaces`, using `ref.invalidate(...)` / `ref.read(...)` from the notifier's `Ref`. Add `ref.read(patientInvoicesProvider(patientId).future)` to the `Future.wait` list.
2. Add a public `Future<void> refreshSurfaces()` on the notifier that resolves the patient id from the currently loaded invoice and delegates to `_refreshSurfaces`.
3. Call `_refreshSurfaces` at the end of the success path of each mutation method on the notifier.
4. In `frontend/lib/features/billing/presentation/pages/invoice_detail_page.dart`, replace both `refreshInvoiceBillingSurfaces(ref, ...)` calls (lines 196 and 209) with the corresponding notifier calls; after **H4** the void path becomes a single `voidInvoice(reason:)` call and needs no explicit refresh at all.
5. In `frontend/lib/features/billing/presentation/widgets/invoice_row_context_menu.dart`, replace the line 192 call the same way.
6. Delete `refreshInvoiceBillingSurfaces` from `presentation/providers/invoice_detail_provider.dart`. If the file no longer needs `flutter_riverpod`'s `WidgetRef`, the import stays for the provider declarations but the `WidgetRef` usage disappears.
7. Run `rg -n "refreshInvoiceBillingSurfaces" frontend/lib` and confirm zero matches.
8. Verify: record a payment, record a refund, and void an invoice, each from both the detail page and (for void) the list row; after each, confirm without any manual reload that the invoice detail balance, the invoice list row, and the patient profile billing section all reflect the change.

---

# M6 — Duplicated balance labels/colours, discount labels, and three custom divider painters across detail, table, and receipt surfaces

**Severity**: Medium

**Location**
- Balance label and "paid" colour rule, implemented three times:
  - `frontend/lib/features/billing/presentation/widgets/invoice_detail/invoice_totals_panel.dart` — `_PaymentsTotalsContent.build`, lines 305–308 (`isVoided ? 'Balance at void' : 'Balance due'`; success colour when `!isVoided && balance.asDouble <= 0`)
  - `frontend/lib/features/billing/presentation/widgets/invoice_detail/invoice_hero_card.dart` — lines 53–54, same two expressions
  - `frontend/lib/features/billing/presentation/widgets/receipt_print_preview.dart` — line 412, same label switch in PDF form
  - `frontend/lib/features/billing/presentation/widgets/invoice_table.dart` — lines 244–261, same "balance ≤ 0 → success, voided → muted" rule with different styling
- Discount label, implemented three times:
  - `frontend/lib/features/billing/presentation/utils/billing_formatting.dart` — `BillingFormatting.discountLabel`, lines 73–87
  - `frontend/lib/features/billing/presentation/widgets/invoice_detail/invoice_totals_panel.dart` — `_discountKindLabel`, lines 446–459
  - `frontend/lib/features/billing/domain/discount_kind.dart` — `labelFor`, lines 30–38
- Three separate custom painters drawing the same visual idiom:
  - `frontend/lib/features/billing/presentation/widgets/invoice_perforation_divider.dart` (84 lines)
  - `frontend/lib/features/billing/presentation/widgets/invoice_detail/invoice_totals_panel.dart` — `_DashedTopLine` / `_DashedTopLinePainter`, lines 405–444
  - `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart` — `_PerforatedEdge` / `_PerforatedEdgePainter`, ≈ lines 716–754
- Also `frontend/lib/features/billing/presentation/widgets/invoice_detail/invoice_line_items_card.dart` line 39 tests `item.lineDiscountAmount.asDouble > 0` where `invoice_editor_notifier.dart` line 28 tests `!item.lineDiscountAmount.isZero` for the same condition — a `double` comparison substituted for a Decimal one
- Related size issue: `receipt_print_preview.dart` (500 lines) contains `ReceiptPrintPreview`, the whole `_ReceiptPdf` layout, `_ReceiptPalette`, `_ReceiptTypography`, filename sanitisation, and its own status-badge palette at lines 222–235

**Issue**

The same small set of presentation rules — how a balance is labelled, when a balance is styled as settled, how a discount is described, and how a perforated/dashed separator is drawn — is re-implemented per surface. Three of these are money-adjacent semantics rather than pure styling: "Balance at void" versus "Balance due" is a statement about invoice state, and "balance ≤ 0 means settled" is the `paid` predicate from `docs/specs/007-billing/invoice-status-cycle.md` ("`paid` means `balance ≤ 0`") re-expressed in widget code, once via `Money.asDouble` comparisons rather than `Money.isPositive`.

**Why it is a problem**

Four copies of a label switch means a wording change requires finding all four, and the PDF copy will inevitably drift from the on-screen copies since it is edited for different reasons. The `asDouble <= 0` and `asDouble > 0` comparisons reintroduce floating point into a predicate that `Money` can answer exactly (`isPositive` / `isZero`), which is the same class of mistake as **C3** in miniature. Three painters for one visual idiom is straightforward duplication with a maintenance cost and no benefit. None of this is severe individually; collectively it is the reason the feature has ~1700 lines of presentation code doing the work of considerably less.

**Recommended architectural solution**

Centralise the three semantics and collapse the painters. Keep the PDF/Flutter split where it is genuinely required (different rendering primitives), but share the *strings and predicates*.

- Add to `frontend/lib/features/billing/domain/invoice_detail.dart`: `bool get isSettled => !balance.isPositive;` and to `frontend/lib/features/billing/domain/invoice_status.dart` nothing new (the status already answers `isVoided`).
- New file `frontend/lib/features/billing/presentation/utils/invoice_labels.dart` with `abstract final class InvoiceLabels` exposing `String balanceLabel({required bool isVoided})` and `bool showsSettledStyling({required Money balance, required bool isVoided})`. All four surfaces call these; only the colour token each one applies stays local.
- Keep exactly one discount label implementation: `DiscountKind.labelFor` in `domain/discount_kind.dart` for the kind name, and `BillingFormatting.discountLabel` for the "N% off" / "N.NN off" rendering. Delete `_discountKindLabel` from `invoice_totals_panel.dart` and call `BillingFormatting.discountLabel` instead.
- Keep one painter: promote `frontend/lib/features/billing/presentation/widgets/invoice_perforation_divider.dart` to take the parameters the other two need (dash length, gap, edge side, colour) and delete `_DashedTopLine`/`_DashedTopLinePainter` and `_PerforatedEdge`/`_PerforatedEdgePainter`.
- Split `receipt_print_preview.dart` into `presentation/widgets/receipt/receipt_print_preview.dart` (the `show`/`buildDocument` entry point and filename helpers) and `presentation/widgets/receipt/receipt_pdf_document.dart` (`_ReceiptPdf`, `_ReceiptPalette`, `_ReceiptTypography`).

**Suggested implementation steps**

1. Add `bool get isSettled => !balance.isPositive;` to `InvoiceDetail` in `domain/invoice_detail.dart`, and the equivalent to `InvoiceListItem` in `domain/invoice_list_item.dart`.
2. Create `frontend/lib/features/billing/presentation/utils/invoice_labels.dart` with `InvoiceLabels.balanceLabel({required bool isVoided})` returning `'Balance at void'` / `'Balance due'`, and `InvoiceLabels.showsSettledStyling({required Money balance, required bool isVoided})` returning `!isVoided && !balance.isPositive`.
3. Replace the label/colour expressions in `invoice_totals_panel.dart` lines 305–308, `invoice_hero_card.dart` lines 53–54, `invoice_table.dart` lines 244–261, and `receipt_print_preview.dart` line 412 with calls to `InvoiceLabels`. Each site keeps its own colour token lookup.
4. In `invoice_line_items_card.dart` line 39, change `item.lineDiscountAmount.asDouble > 0` to `item.lineDiscountAmount.isPositive`.
5. Delete `_discountKindLabel` from `invoice_totals_panel.dart` (lines 446–459) and call `BillingFormatting.discountLabel(discountKind, discountValue)` at its single use site.
6. Extend `invoice_perforation_divider.dart` with the parameters needed by the two other painters (dash width, gap width, `Color`, and whether the notches sit on the top or bottom edge). Replace `_DashedTopLine` in `invoice_totals_panel.dart` and `_PerforatedEdge` in `visit_invoice_review_step.dart` with the shared widget, then delete both private painters. Coordinate with **H7** step 2, which otherwise moves `_PerforatedEdge` to a new file — prefer deleting it here and skipping that step.
7. Create the `presentation/widgets/receipt/` directory; move `receipt_print_preview.dart` into it and extract `_ReceiptPdf`, `_ReceiptPalette`, `_ReceiptTypography` into `receipt_pdf_document.dart`. Update the import in `presentation/pages/invoice_detail_page.dart` line 30.
8. Verify with `flutter analyze`, then compare screenshots before and after for: the invoice list balance column (paid, partially paid, voided rows), the invoice detail hero card and both totals panels, the visit-billing review step's perforated edge, and a generated PDF receipt. Every surface must render identically.

---

## What is sound (stated explicitly, so it is not re-litigated)

These areas were examined and found architecturally correct; no changes are recommended.

- **`data/` repositories.** `InvoiceRepository`, `PaymentRepository`, `InsuranceProviderRepository` and `BillingSettingsRepository` are thin, typed RPC wrappers using the shared `AppRpcInvoker` mixin with consistent `migrationHint` / `rpcLogDomain` metadata. They perform input assertions, map unexpected shapes to `StateError`, and return domain types — no presentation formatting, no widget knowledge, no business rules. `expectedUpdatedAt` is threaded through every mutation, so the optimistic-concurrency contract from the backend is honoured uniformly.
- **`Money` as a type** (as distinct from where it lives, per **C2**). Decimal-backed, immutable, with an explicit wire format (`wireValue` rounds to scale 2), a comma-separator guard in `parse`, and `Comparable`. This is the right design; the problems reported are that it is filed in the wrong feature and lacks multiplication, not that it is wrong.
- **`InvoiceStatus`.** Mirrors the SQL enum exactly, with `tryParse`/`wireValue` round-tripping and the `isVoidable` / `isTerminal` predicates matching `docs/specs/007-billing/invoice-status-cycle.md`. No `overdue` or `cancelled` value has crept in.
- **RPC error mapping.** `application/billing_rpc_messages.dart` maps every documented billing error code to a specific, actionable message and falls back sensibly. Keeping this in `application/` rather than in widgets is correct and matches the pattern `visits` uses.
- **`InvoiceEditorNotifier`'s concurrency handling.** `_mutate` snapshots the previous state, sets `isMutating`, restores the snapshot on failure, refetches on success, and translates `STALE_INVOICE` into a typed `InvoiceStaleException` that the page handles by reloading. This is the correct pattern; findings **H4** and **M5** ask for it to be extended to the ledger mutations that currently bypass it, not changed.
- **Provider type selection.** `FutureProvider.autoDispose.family` for reads, `AsyncNotifierProvider` for mutable list/editor state, plain `Provider` for repositories — consistent with the provider-type table in `docs/architecture/07-frontend.md`.
- **Widget lifecycle hygiene.** Every `TextEditingController` in the feature is disposed; `mounted` / `context.mounted` is checked after every `await` preceding a `context` use; every submit path has an in-flight guard (`_submitting`, `_issuing`, `isMutating`, `isSubmitting`). No double-submit defects were found.
- **Permission plumbing.** `PermissionService` exposes one method per billing permission key from `docs/architecture/15-billing.md`, and `AuthRouteGuard` gates the billing routes. Finding **H4** concerns two specific surfaces that fail to consult it, not the design.

